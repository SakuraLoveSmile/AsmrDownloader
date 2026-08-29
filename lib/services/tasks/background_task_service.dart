import 'dart:async';
import 'dart:collection';

import 'package:asmr_downloader/services/cache/batch_cache_service.dart';
import 'package:asmr_downloader/services/cache/cache_library_providers.dart';
import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:asmr_downloader/services/cache/media_library_settings.dart';
import 'package:asmr_downloader/services/download/download_work_context.dart';
import 'package:asmr_downloader/services/library/library_providers.dart';
import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/ui/system_notifier.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum BackgroundTaskKind {
  completeMissing,
  completeMediaLibrary,
  completeWorksLibrary,
  batchCache,
  postProcessDownloadedWork,
}

enum BackgroundTaskStatus {
  queued,
  running,
  completed,
  failed,
  canceled,
}

class BackgroundTask {
  const BackgroundTask({
    required this.id,
    required this.kind,
    required this.title,
    required this.description,
    required this.createdAt,
    this.status = BackgroundTaskStatus.queued,
    this.startedAt,
    this.finishedAt,
    this.processed = 0,
    this.total,
    this.success = 0,
    this.skipped = 0,
    this.failed = 0,
    this.currentSourceId = '',
    this.detail = '',
    this.error,
    this.cancelRequested = false,
  });

  final String id;
  final BackgroundTaskKind kind;
  final String title;
  final String description;
  final DateTime createdAt;
  final BackgroundTaskStatus status;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  /// 已处理条目数。不同任务类型的条目定义不同，但都用于统一进度条。
  final int processed;
  final int? total;
  final int success;
  final int skipped;
  final int failed;
  final String currentSourceId;
  final String detail;
  final String? error;
  final bool cancelRequested;

  bool get isActive =>
      status == BackgroundTaskStatus.queued ||
      status == BackgroundTaskStatus.running;

  bool get isFinished => !isActive;

  double? get progress {
    if (status == BackgroundTaskStatus.completed) return 1.0;
    final totalValue = total;
    if (totalValue == null || totalValue <= 0) return null;
    return (processed / totalValue).clamp(0.0, 1.0).toDouble();
  }

  BackgroundTask copyWith({
    BackgroundTaskStatus? status,
    DateTime? startedAt,
    DateTime? finishedAt,
    int? processed,
    int? total,
    int? success,
    int? skipped,
    int? failed,
    String? currentSourceId,
    String? detail,
    String? error,
    bool? cancelRequested,
  }) {
    return BackgroundTask(
      id: id,
      kind: kind,
      title: title,
      description: description,
      createdAt: createdAt,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      processed: processed ?? this.processed,
      total: total ?? this.total,
      success: success ?? this.success,
      skipped: skipped ?? this.skipped,
      failed: failed ?? this.failed,
      currentSourceId: currentSourceId ?? this.currentSourceId,
      detail: detail ?? this.detail,
      error: error ?? this.error,
      cancelRequested: cancelRequested ?? this.cancelRequested,
    );
  }
}

class BackgroundTaskNotifier extends Notifier<List<BackgroundTask>> {
  final Queue<_QueuedTask> _queue = Queue<_QueuedTask>();
  final Set<String> _cancelRequests = <String>{};
  bool _draining = false;
  int _sequence = 0;
  bool _disposed = false;

  @override
  List<BackgroundTask> build() {
    ref.onDispose(() => _disposed = true);
    return const [];
  }

  String startCompleteMissing({Duration? interval}) {
    final id = _newId('complete');
    final Duration requestInterval =
        interval ?? ref.read(mediaLibraryRequestIntervalProvider);
    _enqueue(
      BackgroundTask(
        id: id,
        kind: BackgroundTaskKind.completeMissing,
        title: '补全媒体库缺失',
        description: '补全已缓存作品缺少的 tracks 和封面',
        createdAt: DateTime.now(),
      ),
      () => _runCompleteMissing(id, interval: requestInterval),
    );
    return id;
  }

  String startCompleteMediaLibrary({Duration? interval}) {
    final id = _newId('media-complete');
    final Duration requestInterval =
        interval ?? ref.read(mediaLibraryRequestIntervalProvider);
    _enqueue(
      BackgroundTask(
        id: id,
        kind: BackgroundTaskKind.completeMediaLibrary,
        title: '一键补全媒体库',
        description: '补全 NAS 作品元数据、原版社团、tracks 和封面',
        createdAt: DateTime.now(),
      ),
      () => _runCompleteMediaLibrary(id, interval: requestInterval),
    );
    return id;
  }

  String startCompleteWorksLibrary({Duration? interval}) {
    final id = _newId('works-complete');
    final Duration requestInterval =
        interval ?? ref.read(mediaLibraryRequestIntervalProvider);
    _enqueue(
      BackgroundTask(
        id: id,
        kind: BackgroundTaskKind.completeWorksLibrary,
        title: '补全作品库数据',
        description: '补全下载作品的元数据、tracks 和封面并回写注册表',
        createdAt: DateTime.now(),
      ),
      () => _runCompleteWorksLibrary(id, interval: requestInterval),
    );
    return id;
  }

  String startBatchCache({
    required BatchCacheDimension dimension,
    required String name,
    Duration? interval,
  }) {
    final id = _newId('batch');
    final requestInterval =
        interval ?? ref.read(mediaLibraryRequestIntervalProvider);
    final label = switch (dimension) {
      BatchCacheDimension.tag => '标签',
      BatchCacheDimension.circle => '社团',
      BatchCacheDimension.va => 'CV',
    };
    _enqueue(
      BackgroundTask(
        id: id,
        kind: BackgroundTaskKind.batchCache,
        title: '主动缓存 · $name',
        description: '按$label搜索并缓存 workInfo',
        createdAt: DateTime.now(),
      ),
      () => _runBatchCache(
        id,
        dimension: dimension,
        name: name,
        interval: requestInterval,
      ),
    );
    return id;
  }

  /// 下载完成作品的后台后处理：自动整理 + AI 字幕。
  /// 使用下载上下文快照，与下载循环解耦——作品 B 无需等待作品 A 的
  /// 后处理即可开始下载；后处理失败不回写下载状态（状态独立）。
  String startPostProcessDownloadedWork(DownloadWorkContext ctx) {
    final id = _newId('post-process');
    _enqueue(
      BackgroundTask(
        id: id,
        kind: BackgroundTaskKind.postProcessDownloadedWork,
        title: '后处理 ${ctx.sourceId}',
        description: '自动整理 / AI 字幕',
        createdAt: DateTime.now(),
      ),
      () => _runPostProcess(id, ctx),
    );
    return id;
  }

  Future<void> _runPostProcess(String id, DownloadWorkContext ctx) async {
    final ui = ref.read(uiServiceProvider);
    final autoOrganize = ref.read(autoOrganizeProvider);
    final autoTranscribe = ref.read(autoTranscribeProvider);

    if (autoOrganize) {
      _update(id, detail: '正在整理 ${ctx.sourceId}…');
      try {
        await ui.autoOrganizeDownloadedWork(ctx);
      } catch (e) {
        Log.warning('post-process organize failed: ${ctx.sourceId}\n'
            'error: $e');
        _update(
          id,
          status: BackgroundTaskStatus.failed,
          finishedAt: DateTime.now(),
          error: '自动整理失败：$e',
        );
        // 整理失败不继续 AI 字幕（产物未就绪）
        return;
      }
    }

    if (autoTranscribe) {
      _update(id, detail: '正在 AI 字幕 ${ctx.sourceId}…');
      try {
        await ui.autoTranscribe(ctx.sourceId, ctx.sourceDir);
      } catch (e) {
        Log.warning('post-process transcribe failed: ${ctx.sourceId}\n'
            'error: $e');
        _update(
          id,
          status: BackgroundTaskStatus.failed,
          finishedAt: DateTime.now(),
          error: 'AI 字幕失败：$e',
        );
        return;
      }
    }

    _update(
      id,
      status: BackgroundTaskStatus.completed,
      finishedAt: DateTime.now(),
      detail: '后处理完成',
    );
  }

  void cancelTask(String id) {
    final task = _find(id);
    if (task == null || !task.isActive) return;

    _cancelRequests.add(id);
    if (task.status == BackgroundTaskStatus.queued) {
      _update(
        id,
        status: BackgroundTaskStatus.canceled,
        finishedAt: DateTime.now(),
        detail: '任务尚未开始，已取消',
        cancelRequested: true,
      );
    } else {
      _update(id, cancelRequested: true, detail: '正在停止，当前作品完成后结束');
    }
  }

  void clearFinished() {
    state = state.where((task) => task.isActive).toList(growable: false);
  }

  int get activeCount => state.where((task) => task.isActive).length;

  String _newId(String prefix) {
    _sequence++;
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_sequence';
  }

  void _enqueue(BackgroundTask task, Future<void> Function() runner) {
    state = [...state, task];
    _queue.add(_QueuedTask(task.id, runner));
    _drain();
  }

  void _drain() {
    if (_draining) return;
    _draining = true;
    unawaited(_drainQueue());
  }

  Future<void> _drainQueue() async {
    try {
      while (_queue.isNotEmpty) {
        final queued = _queue.removeFirst();
        final task = _find(queued.id);
        if (task == null || task.status == BackgroundTaskStatus.canceled) {
          continue;
        }
        if (_cancelRequests.contains(queued.id)) {
          _update(
            queued.id,
            status: BackgroundTaskStatus.canceled,
            finishedAt: DateTime.now(),
            detail: '任务尚未开始，已取消',
            cancelRequested: true,
          );
          continue;
        }

        _update(
          queued.id,
          status: BackgroundTaskStatus.running,
          startedAt: DateTime.now(),
          detail: '任务运行中',
        );
        try {
          await queued.runner();
        } catch (error, stackTrace) {
          Log.error(
            'background task failed: ${queued.id}\n'
            'error: $error\n$stackTrace',
          );
          _update(
            queued.id,
            status: BackgroundTaskStatus.failed,
            finishedAt: DateTime.now(),
            error: error.toString(),
            detail: '任务执行失败',
          );
        }
      }
    } finally {
      _draining = false;
      if (_queue.isNotEmpty) _drain();
    }
  }

  Future<void> _runCompleteMissing(
    String id, {
    required Duration interval,
  }) async {
    var lastCoverCount = 0;
    final result = await ref.read(cacheCompleteServiceProvider).completeMissing(
          runInterval: interval,
          onProgress: (progress) {
            if (progress.coversFilled > lastCoverCount &&
                progress.currentSourceId.isNotEmpty) {
              ref.invalidate(cachedCoverProvider(progress.currentSourceId));
            }
            lastCoverCount = progress.coversFilled;
            _update(
              id,
              processed: progress.tracksFilled +
                  progress.coversFilled +
                  progress.failed,
              total: progress.totalTracksMissing + progress.totalCoversMissing,
              success: progress.tracksFilled + progress.coversFilled,
              failed: progress.failed,
              currentSourceId: progress.currentSourceId,
              detail:
                  'tracks ${progress.tracksFilled} · 封面 ${progress.coversFilled}',
            );
          },
          isCancelled: () => _cancelRequests.contains(id),
        );

    if (!_disposed) ref.invalidate(cachedLibraryProvider);
    final canceled = result.cancelled || _cancelRequests.contains(id);
    _update(
      id,
      status: canceled
          ? BackgroundTaskStatus.canceled
          : BackgroundTaskStatus.completed,
      finishedAt: DateTime.now(),
      success: result.tracksFilled + result.coversFilled,
      failed: result.failed,
      detail:
          'tracks ${result.tracksFilled} · 封面 ${result.coversFilled} · 失败 ${result.failed}',
      cancelRequested: canceled ? true : null,
    );
    _cancelRequests.remove(id);
  }

  Future<void> _runCompleteMediaLibrary(
    String id, {
    required Duration interval,
  }) async {
    var lastCoverCount = 0;
    final result =
        await ref.read(cacheCompleteServiceProvider).completeMediaLibrary(
              runInterval: interval,
              onProgress: (progress) {
                if (progress.coversFilled > lastCoverCount &&
                    progress.currentSourceId.isNotEmpty) {
                  ref.invalidate(cachedCoverProvider(progress.currentSourceId));
                }
                lastCoverCount = progress.coversFilled;
                final successfulWorks =
                    progress.processed - progress.skipped - progress.failed;
                _update(
                  id,
                  processed: progress.processed,
                  total: progress.total,
                  success: successfulWorks,
                  skipped: progress.skipped,
                  failed: progress.failed,
                  currentSourceId: progress.currentSourceId,
                  detail: '元数据 ${progress.metadataFilled} · '
                      '原版社团 ${progress.originalCirclesFilled} · '
                      'tracks ${progress.tracksFilled} · '
                      '封面 ${progress.coversFilled} · ${progress.phase}',
                );
              },
              isCancelled: () => _cancelRequests.contains(id),
            );

    if (!_disposed) ref.invalidate(cachedLibraryProvider);
    final canceled = result.cancelled || _cancelRequests.contains(id);
    final successfulWorks = result.processed - result.skipped - result.failed;
    _update(
      id,
      status: canceled
          ? BackgroundTaskStatus.canceled
          : BackgroundTaskStatus.completed,
      finishedAt: DateTime.now(),
      processed: result.processed,
      total: result.total,
      success: successfulWorks,
      skipped: result.skipped,
      failed: result.failed,
      detail: '元数据 ${result.metadataFilled} · '
          '原版社团 ${result.originalCirclesFilled} · '
          'tracks ${result.tracksFilled} · '
          '封面 ${result.coversFilled}',
      cancelRequested: canceled ? true : null,
    );
    _cancelRequests.remove(id);
  }

  Future<void> _runCompleteWorksLibrary(
    String id, {
    required Duration interval,
  }) async {
    var lastCoverCount = 0;
    final result =
        await ref.read(cacheCompleteServiceProvider).completeWorksLibrary(
              runInterval: interval,
              onProgress: (progress) {
                if (progress.coversFilled > lastCoverCount &&
                    progress.currentSourceId.isNotEmpty) {
                  ref.invalidate(cachedCoverProvider(progress.currentSourceId));
                }
                lastCoverCount = progress.coversFilled;
                final successfulWorks =
                    progress.processed - progress.skipped - progress.failed;
                _update(
                  id,
                  processed: progress.processed,
                  total: progress.total,
                  success: successfulWorks,
                  skipped: progress.skipped,
                  failed: progress.failed,
                  currentSourceId: progress.currentSourceId,
                  detail: '元数据 ${progress.metadataFilled} · '
                      '注册表 ${progress.indexFilled} · '
                      'tracks ${progress.tracksFilled} · '
                      '封面 ${progress.coversFilled} · ${progress.phase}',
                );
              },
              isCancelled: () => _cancelRequests.contains(id),
            );

    // 完成后刷新作品库与封面/媒体库缓存
    if (!_disposed) {
      ref.invalidate(cachedLibraryProvider);
      ref.invalidate(worksLibraryProvider);
    }
    final canceled = result.cancelled || _cancelRequests.contains(id);
    final successfulWorks = result.processed - result.skipped - result.failed;
    _update(
      id,
      status: canceled
          ? BackgroundTaskStatus.canceled
          : BackgroundTaskStatus.completed,
      finishedAt: DateTime.now(),
      processed: result.processed,
      total: result.total,
      success: successfulWorks,
      skipped: result.skipped,
      failed: result.failed,
      detail: '元数据 ${result.metadataFilled} · '
          '注册表 ${result.indexFilled} · '
          'tracks ${result.tracksFilled} · '
          '封面 ${result.coversFilled}',
      cancelRequested: canceled ? true : null,
    );
    _cancelRequests.remove(id);
  }

  Future<void> _runBatchCache(
    String id, {
    required BatchCacheDimension dimension,
    required String name,
    Duration? interval,
  }) async {
    final result = await ref.read(batchCacheServiceProvider).batchCache(
          dimension,
          name,
          runInterval: interval,
          onProgress: (progress) {
            _update(
              id,
              processed: progress.cached + progress.skipped + progress.failed,
              total: progress.total,
              success: progress.cached,
              skipped: progress.skipped,
              failed: progress.failed,
              currentSourceId: progress.currentSourceId,
              detail:
                  '缓存 ${progress.cached} · 跳过 ${progress.skipped} · 失败 ${progress.failed}',
            );
          },
          isCancelled: () => _cancelRequests.contains(id),
        );

    if (!_disposed) ref.invalidate(cachedLibraryProvider);
    final canceled = result.cancelled || _cancelRequests.contains(id);
    _update(
      id,
      status: canceled
          ? BackgroundTaskStatus.canceled
          : BackgroundTaskStatus.completed,
      finishedAt: DateTime.now(),
      total: result.total,
      processed: result.cached + result.skipped + result.failed,
      success: result.cached,
      skipped: result.skipped,
      failed: result.failed,
      detail:
          '缓存 ${result.cached} · 跳过 ${result.skipped} · 失败 ${result.failed}',
      cancelRequested: canceled ? true : null,
    );
    _cancelRequests.remove(id);
  }

  BackgroundTask? _find(String id) {
    for (final task in state) {
      if (task.id == id) return task;
    }
    return null;
  }

  void _update(
    String id, {
    BackgroundTaskStatus? status,
    DateTime? startedAt,
    DateTime? finishedAt,
    int? processed,
    int? total,
    int? success,
    int? skipped,
    int? failed,
    String? currentSourceId,
    String? detail,
    String? error,
    bool? cancelRequested,
  }) {
    if (_disposed) return;
    final index = state.indexWhere((task) => task.id == id);
    if (index < 0) return;
    final prev = state[index];
    final updated = prev.copyWith(
      status: status,
      startedAt: startedAt,
      finishedAt: finishedAt,
      processed: processed,
      total: total,
      success: success,
      skipped: skipped,
      failed: failed,
      currentSourceId: currentSourceId,
      detail: detail,
      error: error,
      cancelRequested: cancelRequested,
    );
    final next = [...state];
    next[index] = updated;
    state = next;

    if (status != null && prev.status != status) {
      if (status == BackgroundTaskStatus.completed) {
        final info = updated.detail.isNotEmpty ? '：${updated.detail}' : '';
        ref.read(systemNotifierProvider).notify(
              '后台任务完成',
              '${updated.title} 已完成$info',
            );
      } else if (status == BackgroundTaskStatus.failed) {
        final err = updated.error != null && updated.error!.isNotEmpty
            ? '：${updated.error}'
            : '';
        ref.read(systemNotifierProvider).notify(
              '后台任务失败',
              '${updated.title} 执行失败$err',
            );
      }
    }
  }
}

class _QueuedTask {
  const _QueuedTask(this.id, this.runner);

  final String id;
  final Future<void> Function() runner;
}

final backgroundTaskProvider =
    NotifierProvider<BackgroundTaskNotifier, List<BackgroundTask>>(
  BackgroundTaskNotifier.new,
);

final backgroundTaskActiveCountProvider = Provider<int>((ref) {
  return ref
      .watch(backgroundTaskProvider)
      .where((task) => task.isActive)
      .length;
});
