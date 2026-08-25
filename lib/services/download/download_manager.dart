import 'dart:io';
import 'dart:math' as math;

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/api_providers.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/download/download_queue.dart';
import 'package:asmr_downloader/services/download/multi_thread_downloader.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/work_info_providers.dart';
import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/services/library/library_providers.dart';
import 'package:asmr_downloader/services/library/media_library_service.dart';
import 'package:asmr_downloader/services/library/work_library_status.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/tracks_providers.dart';
import 'package:asmr_downloader/services/ui/system_notifier.dart';
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

/// 单次 run 下载结果的简化分类，供队列循环决定是否继续下一个。
/// completed = 全部成功；failed = 部分失败；aborted = 被取消或被新一轮抢占。
enum _RunOutcome { completed, failed, aborted }

/// 下载开始时对作品上下文的快照。下载中允许搜索新作品，
/// 若收尾时重读全局 provider 会把注册表写成新作品的数据，
/// 故在此快照，收尾一律用快照值。
class _RunContext {
  final String sourceId;
  final String voiceWorkPath;
  final String downloadPath;
  final String title;
  final List<String> cvNames;
  final String circleName;
  final String releaseDate;
  final List<String> tags;
  final String coverUrl;

  _RunContext({
    required this.sourceId,
    required this.voiceWorkPath,
    required this.downloadPath,
    required this.title,
    required this.cvNames,
    required this.circleName,
    required this.releaseDate,
    required this.tags,
    required this.coverUrl,
  });
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

  /// 是否正处在队列下载循环中（区别于单次手动下载）。
  /// 队列循环会在作品间自动衔接，取消时终止整个循环。
  bool _inQueueLoop = false;

  /// 队列本轮累计的成功/失败计数，循环结束后统一提示。
  int _queueSuccessCnt = 0;
  int _queueFailedCnt = 0;

  /// 防止用户连续点击「下载」/「继续下载」启动两条相互抢占的循环。
  bool _runInFlight = false;

  /// 下载入口：手动点击或队列循环调用。
  /// 外层 while 循环串行处理队列中的作品，作品内沿用文件级并行。
  /// 第一个作品（手动下载）完成后会继续处理下载期间入队的作品，
  /// 仅当确实处理了队列作品时才提示队列统计。
  Future<void> run() async {
    if (_runInFlight ||
        ref.read(dlStatusProvider) == DownloadStatus.downloading) {
      return;
    }

    _runInFlight = true;
    final runSeq = ++_runSeq;
    _currentRunSeq = runSeq;
    _cancelRequested = false;
    _inQueueLoop = false;
    _queueSuccessCnt = 0;
    _queueFailedCnt = 0;

    try {
      while (true) {
        final outcome = await _runOnce(runSeq);
        if (runSeq != _runSeq) return; // 被新一轮抢占
        if (_cancelRequested) {
          // 用户取消：终止整个队列循环，条目保留
          _finalizeQueueIfLoop(runSeq, canceled: true);
          return;
        }
        if (outcome == _RunOutcome.aborted) {
          // 校验失败等：结束（取消已在上面处理）
          return;
        }

        // 当前作品已完成/失败，计入统计（是否对外提示取决于是否进队列）
        if (outcome == _RunOutcome.completed) {
          _queueSuccessCnt++;
        } else {
          _queueFailedCnt++;
        }

        // 尝试从队列取下一个作品（下载期间用户可能已入队）
        final prepared = await _prepareNextQueuedWork(runSeq);
        if (runSeq != _runSeq) return;
        if (!prepared) {
          // 队列空：若已进入队列模式则提示统计，否则静默结束（纯单次下载）
          _finalizeQueueIfLoop(runSeq, canceled: false);
          return;
        }
        _inQueueLoop = true;
      }
    } finally {
      if (runSeq == _runSeq) _runInFlight = false;
    }
  }

  /// 单次下载执行（一个作品）。返回结果分类。
  /// [runSeq] 为本轮 run() 的序号，用于抢占判断。
  Future<_RunOutcome> _runOnce(int runSeq) async {
    _activeCancelTokens.clear();
    _failedCnt = 0;

    await ref.read(uiServiceProvider).resetProgress();

    // handle error

    final sourceId = ref.read(sourceIdProvider);
    if (sourceId == null) {
      Log.fatal('download failed\n' 'error: sourceId is null');
      ref.read(uiServiceProvider).showSnack('下载失败：请先搜索作品');
      return _RunOutcome.aborted;
    }

    // 媒体库扫描只记录 RJ 号，因此本机下载根目录里的断点目录不会阻止
    // 恢复；但 NAS/其它扫描根目录已有记录时，直接阻止重复下载。
    final existingExternalCopy =
        await ref.read(mediaLibraryServiceProvider).findExistingOutsideRoot(
              sourceId: sourceId,
              excludedRoot: ref.read(downloadPathProvider),
            );
    if (existingExternalCopy != null) {
      // 刚执行过实时重扫，同步刷新搜索页的入库状态徽章
      ref.invalidate(workLibraryStatusProvider);
      ref.read(uiServiceProvider).showSnack(
            '媒体库已存在 $sourceId（${existingExternalCopy.matchedPath}），已跳过重复下载',
          );
      return _RunOutcome.aborted;
    }

    // 标题/目录名为空（title 降级链尚未给出保底值）时拒绝下载
    final voiceWorkPath = ref.read(voiceWorkPathProvider);
    if (p.basename(voiceWorkPath) == '-' ||
        p.equals(voiceWorkPath, ref.read(downloadPathProvider))) {
      Log.error('download failed: $sourceId\n'
          'error: voiceWorkPath is invalid, which means you have to start downloading after work info is loaded');
      ref.read(uiServiceProvider).showSnack('下载失败：请等待作品信息加载完成后再下载');
      return _RunOutcome.aborted;
    }

    ref.read(currentDownloadingSourceIdProvider.notifier).state = sourceId;
    ref.read(lastDownloadSourceIdProvider.notifier).state = sourceId;

    // 下载开始即快照作品上下文：下载中允许搜索新作品，
    // 收尾写注册表时全部用快照值，避免被搜索切走的新作品数据污染。
    final ctx = await _snapshotRunContext(sourceId, voiceWorkPath);
    if (runSeq != _runSeq) {
      ref.read(currentDownloadingSourceIdProvider.notifier).state = null;
      return _RunOutcome.aborted;
    }

    // start downloading

    ref.read(dlStatusProvider.notifier).state = DownloadStatus.downloading;
    ref.read(currentDlNoProvider.notifier).state = 0;

    final rootFolderSnapshot = ref.read(rootFolderProvider)?.copyWith();
    if (rootFolderSnapshot == null) {
      Log.fatal(
          'download tracks failed: $sourceId\n' 'error: rootFolder is null');
      ref.read(uiServiceProvider).showSnack('下载失败：音轨列表为空，请重新搜索');
      ref.read(currentDownloadingSourceIdProvider.notifier).state = null;
      return _RunOutcome.aborted;
    }

    // 拍平所有下载任务：封面优先，随后按音轨树先序收集选中文件
    final tasks = await _collectTasks(rootFolderSnapshot, voiceWorkPath);
    if (_cancelRequested || runSeq != _runSeq) {
      ref.read(currentDownloadingSourceIdProvider.notifier).state = null;
      return _RunOutcome.aborted;
    }

    _tasks = tasks;
    _nextTaskIndex = 0;
    _activeTasks.clear();
    _completedBytes = 0;
    _totalBytes = tasks.fold(0, (sum, t) => sum + math.max(0, t.size));

    ref.read(totalTaskCntProvider.notifier).state = tasks.length;
    ref.read(totalBytesProvider.notifier).state = _totalBytes;
    // 立即发布一轮全排队状态的分段，让进度条先展示文件构成
    _refreshAggregateProgress(force: true);

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
      ref.read(currentDownloadingSourceIdProvider.notifier).state = null;
      return _RunOutcome.aborted;
    }

    if (_failedCnt > 0) {
      Log.error('download failed: $sourceId\n'
          'failed task count: $_failedCnt');
      ref.read(dlStatusProvider.notifier).state = DownloadStatus.failed;
      ref.read(uiServiceProvider).showSnack('下载失败：$_failedCnt 个文件下载失败，可点击「重试」');
      ref.read(currentDownloadingSourceIdProvider.notifier).state = null;
      return _RunOutcome.failed;
    }

    ref.read(dlStatusProvider.notifier).state = DownloadStatus.completed;

    // 写入下载注册表（批量整理的数据源）；
    // 自动整理成功后会由 organizeCurrentWork 补录 organizedAt。
    // 全部用快照值，不受下载中搜索切走的作品影响。
    try {
      await ref.read(worksIndexProvider).upsert(WorkEntry(
            sourceId: ctx.sourceId,
            dlPath: ctx.downloadPath,
            dirName: p.basename(ctx.voiceWorkPath),
            title: ctx.title,
            cvNames: ctx.cvNames.join('&'),
            circleName: ctx.circleName,
            releaseDate: ctx.releaseDate,
            tags: ctx.tags,
            coverUrl: ctx.coverUrl,
          ));
    } catch (e) {
      ref.read(uiServiceProvider).showSnack('作品已下载，但注册表写入失败（$e），可手动整理');
    }
    // 新作品入库：刷新作品库列表与 badge，以及搜索页的入库状态徽章
    ref.invalidate(worksLibraryProvider);
    ref.invalidate(unorganizedCountProvider);
    ref.invalidate(workLibraryStatusProvider);
    if (Platform.isWindows) {
      await WindowsTaskbar.setFlashTaskbarAppIcon(
        mode: TaskbarFlashMode.all | TaskbarFlashMode.timernofg,
        flashCount: 5,
        timeout: const Duration(milliseconds: 500),
      );
    }
    await ref.read(systemNotifierProvider).notify('下载完成', '$sourceId 下载已完成');

    ref.read(currentDownloadingSourceIdProvider.notifier).state = null;

    // auto organize to navidrome
    if (ref.read(autoOrganizeProvider)) {
      await ref.read(uiServiceProvider).autoOrganize();
    }

    // auto AI subtitle translate (ChickenRice)
    if (ref.read(autoTranscribeProvider)) {
      await ref.read(uiServiceProvider).autoTranscribe(sourceId);
    }

    return _RunOutcome.completed;
  }

  /// 快照当前作品上下文（run 校验通过后立即调用）。
  /// 社团名经 resolveCircleName 解析为原始社团名（汉化版跟踪原版），
  /// 需异步获取，故本方法为 async。
  Future<_RunContext> _snapshotRunContext(
      String sourceId, String voiceWorkPath) async {
    return _RunContext(
      sourceId: sourceId,
      voiceWorkPath: voiceWorkPath,
      downloadPath: ref.read(downloadPathProvider),
      title: ref.read(titleProvider),
      cvNames: ref.read(cvLsProvider),
      circleName: await ref.read(circleNameProvider.future),
      releaseDate: ref.read(releaseDateProvider),
      tags: ref.read(tagLsProvider),
      coverUrl: ref.read(coverUrlProvider),
    );
  }

  /// 从队列取下一个作品并准备好元数据。返回 true 表示已就绪可进入 _runOnce。
  /// [runSeq] 用于抢占判断。
  Future<bool> _prepareNextQueuedWork(int runSeq) async {
    if (_cancelRequested || runSeq != _runSeq) return false;

    final queueNotifier = ref.read(downloadQueueProvider.notifier);
    final queuedWork = await queueNotifier.peek();
    if (runSeq != _runSeq) return false;
    final nextSourceId = queuedWork?.sourceId;
    if (nextSourceId == null) return false;

    // 搜索队首作品并等待元数据就绪（与 search_box._refresh 同写法，
    // 各带 catchError 兜底），随后进入下一轮 _runOnce。
    await ref.read(uiServiceProvider).search(nextSourceId, silent: true);
    if (runSeq != _runSeq) return false;
    await Future.wait([
      ref.read(workInfoProvider.future),
      ref.read(rawTracksProvider.future),
    ].map((f) => f.catchError((_) => null)));
    if (runSeq != _runSeq) return false;

    // 先确认搜索和音轨都成功，再从队列移除。这样 API/网络异常时，
    // 条目会继续留在队列里，用户可以稍后重试，而不会无声丢失。
    final tracks = ref.read(rawTracksProvider);
    final rootFolder = ref.read(rootFolderProvider);
    final prepared = ref.read(sourceIdProvider) == nextSourceId &&
        tracks.hasValue &&
        tracks.value != null &&
        rootFolder != null;
    if (!prepared) {
      ref
          .read(uiServiceProvider)
          .showSnack('队列作品 $nextSourceId 加载失败，条目已保留，可稍后重试');
      return false;
    }

    // 重新搜索会构建一棵全新的音轨树；恢复入队时保存的文件选择，
    // 非 null（包括空列表）表示严格恢复，null 则兼容旧版队列的全选行为。
    applySelectedFileIds(rootFolder, queuedWork!.selectedTrackIds);
    ref.read(rootFolderProvider.notifier).state = rootFolder;

    // 仅当队首仍未被用户移除时才消费它，避免异步加载期间错删下一个条目。
    final claimed = await queueNotifier.popFrontIf(nextSourceId);
    if (!claimed) {
      // 用户可能在元数据加载期间移除了原队首；继续尝试新的队首，
      // 不让一个合法的移除操作意外中断整个下载循环。
      if (_cancelRequested || runSeq != _runSeq) return false;
      return _prepareNextQueuedWork(runSeq);
    }
    return true;
  }

  /// 队列循环结束时统一提示（仅队列模式下有意义）。
  /// 单次手动下载（未进队列）不提示。
  void _finalizeQueueIfLoop(int runSeq, {required bool canceled}) {
    if (runSeq != _runSeq) return;
    if (!_inQueueLoop) return;
    if (canceled) {
      ref.read(uiServiceProvider).showSnack('已取消下载队列（已完成 $_queueSuccessCnt 个）');
    } else {
      ref
          .read(uiServiceProvider)
          .showSnack('队列下载完成：$_queueSuccessCnt 成功，$_queueFailedCnt 失败');
    }
  }

  /// 从队列启动下载（无当前搜索时，供队列面板「继续下载」按钮调用）。
  /// 非下载中且队列非空时：准备队首、搜索、确认元数据后进入 run 循环。
  Future<void> startFromQueue() async {
    if (_runInFlight ||
        ref.read(dlStatusProvider) == DownloadStatus.downloading) {
      return;
    }

    final queueNotifier = ref.read(downloadQueueProvider.notifier);
    await queueNotifier.waitUntilReady();
    if (_runInFlight ||
        ref.read(dlStatusProvider) == DownloadStatus.downloading) {
      return;
    }
    if (await queueNotifier.peek() == null) return;

    _runInFlight = true;
    _inQueueLoop = true;
    _queueSuccessCnt = 0;
    _queueFailedCnt = 0;
    final runSeq = ++_runSeq;
    _currentRunSeq = runSeq;
    _cancelRequested = false;

    try {
      final firstPrepared = await _prepareNextQueuedWork(runSeq);
      if (runSeq != _runSeq) return;
      if (!firstPrepared) {
        // 加载失败时条目仍保留在队列中；不显示「队列完成」误导用户。
        return;
      }

      while (true) {
        final outcome = await _runOnce(runSeq);
        if (runSeq != _runSeq) return;
        if (_cancelRequested) {
          _finalizeQueueIfLoop(runSeq, canceled: true);
          return;
        }
        if (outcome == _RunOutcome.aborted) {
          // 校验失败等：结束（取消已在上面处理）
          return;
        }
        if (outcome == _RunOutcome.completed) {
          _queueSuccessCnt++;
        } else {
          _queueFailedCnt++;
        }
        final nextPrepared = await _prepareNextQueuedWork(runSeq);
        if (runSeq != _runSeq) return;
        if (!nextPrepared) {
          _finalizeQueueIfLoop(runSeq, canceled: false);
          return;
        }
      }
    } finally {
      if (runSeq == _runSeq) _runInFlight = false;
    }
  }

  /// 取消全部下载任务：置 canceled 状态并 cancel 本轮所有在途 CancelToken。
  /// 已开始的请求立即中断，尚未开始的任务会通过 [_cancelRequested] 跳过。
  /// 队列模式下同时阻断 while 循环（不再启动下一个队列作品）。
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
    _refreshAggregateProgress(force: true);

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
    ref.read(downloadedBytesProvider.notifier).state = doneBytes;
    _publishSegments();

    final remaining = math.max(0, _totalBytes - doneBytes);
    ref.read(downloadEtaProvider.notifier).state = totalSpeed > 0
        ? Duration(seconds: (remaining / totalSpeed).round())
        : Duration.zero;
  }

  /// 发布本轮全部任务的分段进度（含排队/下载中/完成/失败），供分段进度条展示。
  void _publishSegments() {
    ref.read(downloadSegmentsProvider.notifier).state = [
      for (final task in _tasks)
        DownloadSegment(
          title: task.title,
          size: math.max(task.size, 0),
          fraction: task.status == DownloadStatus.completed
              ? 1.0
              : task.size > 0
                  ? (task.receivedBytes / task.size).clamp(0.0, 1.0)
                  : task.progress,
          status: task.status,
          speed: task.currentSpeed,
        ),
    ];
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
