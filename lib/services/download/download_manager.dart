import 'dart:io';
import 'dart:math' as math;

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/api_providers.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/download/multi_thread_downloader.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/work_info_providers.dart';
import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/services/library/library_providers.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:windows_taskbar/windows_taskbar.dart';

import 'package:path/path.dart' as p;

enum _DownloadTaskKind {
  /// 普通网络下载（音轨、无缓存字节时的封面）
  network,

  /// 内存字节直接写盘（coverBytesProvider 已就绪时的封面）
  memory,
}

class _DownloadTask {
  _DownloadTask({
    required this.id,
    required this.title,
    required this.savePath,
    required this.url,
    required this.size,
    required this.kind,
    this.bytes,
  });

  final String id;
  final String title;
  final String savePath;
  final String url;
  final int size;
  final _DownloadTaskKind kind;
  final List<int>? bytes;

  final CancelToken cancelToken = CancelToken();
  DownloadStatus status = DownloadStatus.notStarted;

  // ---- 进度聚合用 ----
  int receivedBytes = 0;
  int lastReceivedBytes = 0;
  double currentSpeed = 0;
  double progress = 0;
  final Stopwatch stopwatch = Stopwatch();
  int finalBytes = 0; // 完成后实际计入总进度的字节数
}

class DownloadManager {
  final Ref ref;
  DownloadManager(this.ref);

  /// 最新一轮 run() 的序号（新一轮 run 会使旧一轮让位）
  int _runSeq = 0;

  /// 当前正在执行下载循环的那一轮序号
  int _currentRunSeq = 0;

  /// 用户请求取消（cancelAllDownload 置位，run() 开始时复位）
  bool _cancelRequested = false;

  /// 本轮正在下载的所有 CancelToken（含封面），取消时统一 cancel
  final Set<CancelToken> _activeCancelTokens = {};

  /// 本轮下载失败（返回 false）的文件数
  int _failedCnt = 0;

  // ---- 并行下载任务队列 ----
  List<_DownloadTask> _tasks = const [];
  int _nextTaskIndex = 0;
  final Set<_DownloadTask> _activeTasks = {};

  // ---- 全局进度聚合 ----
  int _completedBytes = 0;
  int _totalBytes = 0;
  DateTime _lastAggregateRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> run() async {
    final runSeq = ++_runSeq;
    _currentRunSeq = runSeq;
    _cancelRequested = false;
    _activeCancelTokens.clear();
    _failedCnt = 0;

    await ref.read(uiServiceProvider).resetProgress();

    // handle error

    final sourceId = ref.read(sourceIdProvider);
    if (sourceId == null) {
      Log.fatal('download failed\n' 'error: sourceId is null');
      ref.read(uiServiceProvider).showSnack('下载失败：请先搜索作品');
      return;
    }

    // 标题/目录名为空（title 降级链尚未给出保底值）时拒绝下载
    final voiceWorkPath = ref.read(voiceWorkPathProvider);
    if (p.basename(voiceWorkPath) == '-' ||
        p.equals(voiceWorkPath, ref.read(downloadPathProvider))) {
      Log.error('download failed: $sourceId\n'
          'error: voiceWorkPath is invalid, which means you have to start downloading after work info is loaded');
      ref.read(uiServiceProvider).showSnack('下载失败：请等待作品信息加载完成后再下载');
      return;
    }

    // start downloading

    ref.read(dlStatusProvider.notifier).state = DownloadStatus.downloading;
    ref.read(currentDlNoProvider.notifier).state = 0;

    final rootFolderSnapshot = ref.read(rootFolderProvider)?.copyWith();
    if (rootFolderSnapshot == null) {
      Log.fatal(
          'download tracks failed: $sourceId\n' 'error: rootFolder is null');
      ref.read(uiServiceProvider).showSnack('下载失败：音轨列表为空，请重新搜索');
    }

    // 拍平所有下载任务：封面优先，随后按音轨树先序收集选中文件
    final tasks = await _collectTasks(rootFolderSnapshot, voiceWorkPath);
    if (_cancelRequested || runSeq != _runSeq) return;

    _tasks = tasks;
    _nextTaskIndex = 0;
    _activeTasks.clear();
    _completedBytes = 0;
    _totalBytes = tasks.fold(0, (sum, t) => sum + math.max(0, t.size));

    ref.read(totalTaskCntProvider.notifier).state = tasks.length;

    // 启动文件级并行 worker
    final parallelCount = _effectiveParallelCount();
    final workerCount = math.min(parallelCount, tasks.length);
    await Future.wait([
      for (var i = 0; i < workerCount; i++) _worker(),
    ]);

    // download finished (completed / canceled / failed)

    // 新一轮 run 已经开始，或用户取消了下载：放弃收尾，避免旧流程覆盖新状态
    if (runSeq != _runSeq ||
        ref.read(dlStatusProvider) == DownloadStatus.canceled) {
      Log.info('download aborted: $sourceId');
      return;
    }

    if (_failedCnt > 0) {
      Log.error('download failed: $sourceId\n'
          'failed task count: $_failedCnt');
      ref.read(dlStatusProvider.notifier).state = DownloadStatus.failed;
      ref.read(uiServiceProvider).showSnack('下载失败：$_failedCnt 个文件下载失败，可点击「重试」');
      return;
    }

    ref.read(dlStatusProvider.notifier).state = DownloadStatus.completed;

    // 写入下载注册表（批量整理的数据源）；
    // 自动整理成功后会由 organizeCurrentWork 补录 organizedAt
    await ref.read(worksIndexProvider).upsert(WorkEntry(
          sourceId: sourceId,
          dlPath: ref.read(downloadPathProvider),
          dirName: p.basename(voiceWorkPath),
          title: ref.read(titleProvider),
          cvNames: ref.read(cvLsProvider).join('&'),
          circleName: ref.read(circleNameProvider),
          releaseDate: ref.read(releaseDateProvider),
          tags: ref.read(tagLsProvider),
          coverUrl: ref.read(coverUrlProvider),
        ));
    // 新作品入库：刷新作品库列表与 badge
    ref.invalidate(worksLibraryProvider);
    ref.invalidate(unorganizedCountProvider);
    if (Platform.isWindows) {
      await WindowsTaskbar.setFlashTaskbarAppIcon(
        mode: TaskbarFlashMode.all | TaskbarFlashMode.timernofg,
        flashCount: 5,
        timeout: const Duration(milliseconds: 500),
      );
    }

    // auto organize to navidrome
    if (ref.read(autoOrganizeProvider)) {
      await ref.read(uiServiceProvider).autoOrganize();
    }

    // auto AI subtitle translate (ChickenRice)
    if (ref.read(autoTranscribeProvider)) {
      await ref.read(uiServiceProvider).autoTranscribe(sourceId);
    }
  }

  /// 取消全部下载任务：置 canceled 状态并 cancel 本轮所有在途 CancelToken。
  /// 已开始的请求立即中断，尚未开始的任务会通过 [_cancelRequested] 跳过。
  void cancelAllDownload() {
    if (ref.read(dlStatusProvider) != DownloadStatus.downloading) return;

    _cancelRequested = true;
    ref.read(dlStatusProvider.notifier).state = DownloadStatus.canceled;

    for (final token in _activeCancelTokens) {
      if (!token.isCancelled) {
        token.cancel('下载已取消');
      }
    }
    Log.info('cancel all downloads');
  }

  int countTotalTask(Folder rootFolder) {
    int totalTaskCnt = 0;
    for (final child in rootFolder.children) {
      if (child is Folder) {
        totalTaskCnt += countTotalTask(child);
      } else if (child.selected) {
        totalTaskCnt++;
      }
    }
    return totalTaskCnt;
  }

  // ------------------------------------------------------------- 任务收集

  Future<List<_DownloadTask>> _collectTasks(
      Folder? rootFolder, String voiceWorkPath) async {
    final tasks = <_DownloadTask>[];

    final coverTask = await _buildCoverTask(voiceWorkPath);
    if (coverTask != null) {
      tasks.add(coverTask);
    }

    if (rootFolder != null) {
      void walk(TrackItem item, String dirPath) {
        final targetPath = p.join(
          dirPath,
          getLegalWindowsName(item.title),
        );
        if (item is Folder) {
          for (final child in item.children) {
            walk(child, targetPath);
          }
        } else if (item is FileAsset) {
          if (item.selected) {
            item.savePath = targetPath;
            tasks.add(_DownloadTask(
              id: item.id,
              title: item.title,
              savePath: targetPath,
              url: item.mediaDownloadUrl,
              size: item.size,
              kind: _DownloadTaskKind.network,
            ));
          }
        }
      }

      walk(rootFolder, voiceWorkPath);
    }

    return tasks;
  }

  /// 构建封面任务：优先使用内存中的封面字节，否则探测 Content-Length 后走网络下载。
  /// 封面字节不可得且无法探测大小时返回 null（与旧逻辑一致：跳过封面）。
  Future<_DownloadTask?> _buildCoverTask(String voiceWorkPath) async {
    if (!ref.read(dlCoverProvider)) return null;

    final sourceId = ref.read(sourceIdProvider)!;
    final savePath = p.join(
      voiceWorkPath,
      sourceId,
      '${sourceId}_cover.jpg',
    );
    final coverName = p.basename(savePath);

    final coverBytesAsync = ref.read(coverBytesProvider);
    final bytes = coverBytesAsync.value;
    if (coverBytesAsync is AsyncData && bytes != null) {
      return _DownloadTask(
        id: coverName,
        title: coverName,
        savePath: savePath,
        url: '',
        size: bytes.length,
        kind: _DownloadTaskKind.memory,
        bytes: bytes,
      );
    }

    final coverUrl = ref.read(coverUrlProvider);
    final int? coverSize =
        await ref.read(asmrApiProvider).tryGetContentLength(coverUrl);
    if (coverSize == null) {
      Log.error('download cover failed: $coverName\n'
          'error: cover size is null');
      return null;
    }

    return _DownloadTask(
      id: coverName,
      title: coverName,
      savePath: savePath,
      url: coverUrl,
      size: coverSize,
      kind: _DownloadTaskKind.network,
    );
  }

  // ------------------------------------------------------------- worker pool

  Future<void> _worker() async {
    while (true) {
      if (_cancelRequested || _runSeq != _currentRunSeq) return;

      final index = _nextTaskIndex++;
      if (index >= _tasks.length) return;

      final task = _tasks[index];
      if (_cancelRequested || _runSeq != _currentRunSeq) return;

      final ok = await _downloadTask(task);
      if (!ok) _failedCnt++;
    }
  }

  /// 并行文件数（只接受 UI 提供的可选值，非法配置回退 2）
  int _effectiveParallelCount() {
    final configured = ref.read(parallelDownloadCountProvider);
    return parallelDownloadOptions.contains(configured) ? configured : 2;
  }

  /// 并行时自动压低单文件线程数，确保总连接数不超过 maxTotalDownloadConnections。
  int _perFileThreads() {
    final parallel = _effectiveParallelCount();
    final configuredThreads = ref.read(downloadThreadsProvider);
    final capped = maxTotalDownloadConnections ~/ parallel;
    return math.max(1, math.min(configuredThreads, capped));
  }

  /// 供测试验证并行时的线程压缩规则。
  int perFileThreadsForTesting() => _perFileThreads();

  // ------------------------------------------------------------- 单个任务

  Future<bool> _downloadTask(_DownloadTask task) async {
    // 已取消或已有新一轮下载开始时，跳过排队中的任务
    if (_cancelRequested || _runSeq != _currentRunSeq) return false;

    task
      ..status = DownloadStatus.downloading
      ..stopwatch.start();
    _activeCancelTokens.add(task.cancelToken);
    _activeTasks.add(task);
    _updateActiveFileNames();

    final ok = task.kind == _DownloadTaskKind.memory
        ? await _writeMemoryTask(task)
        : await _resumableDownload(
            task.url,
            task.savePath,
            task.size,
            cancelToken: task.cancelToken,
            onReceiveProgress: (received, total) {
              _onTaskProgress(task, received, total);
            },
          );

    _activeCancelTokens.remove(task.cancelToken);
    _activeTasks.remove(task);
    task.stopwatch.stop();

    if (ok) {
      task
        ..status = DownloadStatus.completed
        ..progress = 1
        ..finalBytes = math.max(task.receivedBytes, math.max(task.size, 0));
      _completedBytes += task.finalBytes;
      ref.read(currentDlNoProvider.notifier).state++;
    } else {
      task.status = DownloadStatus.failed;
    }

    _updateActiveFileNames();
    _refreshAggregateProgress(force: true);

    if (ok && Platform.isWindows) {
      await WindowsTaskbar.setProgress(
          ref.read(currentDlNoProvider), ref.read(totalTaskCntProvider));
    }

    return ok;
  }

  Future<bool> _writeMemoryTask(_DownloadTask task) async {
    try {
      final file = File(task.savePath);
      await file.create(recursive: true);
      final bytes = task.bytes;
      if (bytes == null) return false;
      if (await file.length() != bytes.length) {
        await file.writeAsBytes(bytes);
      }
      task.receivedBytes = bytes.length;
      return true;
    } catch (e) {
      Log.error('save cover failed: ${task.title}\n'
          'error: $e');
      return false;
    }
  }

  void _onTaskProgress(_DownloadTask task, int received, int total) {
    task.receivedBytes = received;
    if (total > 0) {
      task.progress = received / total;
    }

    // 每 500ms 用增量计算一次该任务的速度，避免累计误差
    final elapsedMs = task.stopwatch.elapsedMilliseconds;
    if (elapsedMs >= 500) {
      task.currentSpeed =
          (received - task.lastReceivedBytes) * 1000 / elapsedMs;
      task.lastReceivedBytes = received;
      task.stopwatch.reset();
    }

    _refreshAggregateProgress();
  }

  // ------------------------------------------------------------- 进度聚合

  void _updateActiveFileNames() {
    final names = _tasks
        .where((task) => _activeTasks.contains(task))
        .map((task) => task.title)
        .toList();
    ref.read(activeFileNamesProvider.notifier).state = names;
    ref.read(currentFileNameProvider.notifier).state = names.isEmpty
        ? ''
        : names.length == 1
            ? names.first
            : '${names.take(2).join('、')}${names.length > 2 ? ' 等 ${names.length} 个文件' : ''}';
  }

  void _refreshAggregateProgress({bool force = false}) {
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastAggregateRefresh) <
            const Duration(milliseconds: 100)) {
      return;
    }
    _lastAggregateRefresh = now;

    var activeReceived = 0;
    var totalSpeed = 0.0;
    for (final task in _activeTasks) {
      activeReceived += math.min(task.receivedBytes, math.max(task.size, 0));
      totalSpeed += task.currentSpeed;
    }

    final doneBytes = _completedBytes + activeReceived;
    final progress = _totalBytes > 0
        ? (doneBytes / _totalBytes).clamp(0.0, 1.0)
        : _fallbackCountProgress();

    ref.read(processProvider.notifier).state = progress;
    ref.read(downloadSpeedProvider.notifier).state = totalSpeed;

    final remaining = math.max(0, _totalBytes - doneBytes);
    ref.read(downloadEtaProvider.notifier).state = totalSpeed > 0
        ? Duration(seconds: (remaining / totalSpeed).round())
        : Duration.zero;
  }

  /// 总字节未知（异常数据）时按文件数兜底。
  double _fallbackCountProgress() {
    if (_tasks.isEmpty) return 0;
    final completed =
        _tasks.where((t) => t.status == DownloadStatus.completed).length;
    var activeFraction = 0.0;
    for (final task in _activeTasks) {
      activeFraction += task.size > 0 ? 0 : task.progress;
    }
    return ((completed + activeFraction) / _tasks.length).clamp(0.0, 1.0);
  }

  /// 单文件下载入口：按用户配置的线程数走多线程分段下载，
  /// 服务器不支持 Range 时由 MultiThreadDownloader 自动回退单线程。
  Future<bool> _resumableDownload(
    String url,
    String savePath,
    int fileSize, {
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) {
    return MultiThreadDownloader(ref.read(asmrApiProvider)).download(
      url: url,
      savePath: savePath,
      fileSize: fileSize,
      threadCount: _perFileThreads(),
      cancelToken: cancelToken,
      onProgress: onReceiveProgress,
    );
  }

  // 取消下载任务
  void cancelDownload(FileAsset task) {
    if (!task.cancelToken.isCancelled) {
      task.cancelToken.cancel('下载已取消');
    }
  }
}
