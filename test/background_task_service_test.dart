import 'package:asmr_downloader/services/cache/batch_cache_service.dart';
import 'package:asmr_downloader/services/cache/cache_complete_service.dart';
import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:asmr_downloader/services/cache/media_library_settings.dart';
import 'package:asmr_downloader/services/tasks/background_task_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCompleteService extends CacheCompleteService {
  _FakeCompleteService(super.ref, {required this.delay});

  final Duration delay;
  int calls = 0;
  Duration? lastRunInterval;

  @override
  Future<CompleteResult> completeMissing({
    Duration? runInterval,
    required void Function(CompleteProgress) onProgress,
    required bool Function() isCancelled,
  }) async {
    calls++;
    lastRunInterval = runInterval;
    onProgress(const CompleteProgress(
      tracksFilled: 1,
      coversFilled: 0,
      failed: 0,
      currentSourceId: 'RJ00001',
      totalTracksMissing: 2,
      totalCoversMissing: 1,
    ));
    await Future<void>.delayed(delay);
    return CompleteResult(
      tracksFilled: 1,
      coversFilled: 0,
      failed: 0,
      cancelled: isCancelled(),
    );
  }
}

class _FakeBatchService extends BatchCacheService {
  _FakeBatchService(super.ref, {required this.delay});

  final Duration delay;
  int calls = 0;
  Duration? lastRunInterval;

  @override
  Future<BatchCacheResult> batchCache(
    BatchCacheDimension dimension,
    String name, {
    Duration? runInterval,
    required void Function(BatchCacheProgress) onProgress,
    required bool Function() isCancelled,
  }) async {
    calls++;
    lastRunInterval = runInterval;
    onProgress(const BatchCacheProgress(
      cached: 1,
      skipped: 0,
      failed: 0,
      currentSourceId: 'RJ00002',
      total: 2,
    ));
    await Future<void>.delayed(delay);
    return BatchCacheResult(
      cached: 1,
      skipped: 0,
      failed: 0,
      cancelled: isCancelled(),
      total: 2,
    );
  }
}

void main() {
  Future<void> waitFor(
    bool Function() predicate, {
    Duration timeout = const Duration(seconds: 1),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!predicate()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('等待后台任务状态超时');
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  ProviderContainer makeContainer({
    Duration completeDelay = const Duration(milliseconds: 8),
    Duration batchDelay = const Duration(milliseconds: 2),
    required void Function(_FakeCompleteService) onComplete,
    required void Function(_FakeBatchService) onBatch,
    Duration mediaInterval = mediaLibraryRequestIntervalDefault,
  }) {
    final container = ProviderContainer(overrides: [
      cacheCompleteServiceProvider.overrideWith((ref) {
        final service = _FakeCompleteService(ref, delay: completeDelay);
        onComplete(service);
        return service;
      }),
      batchCacheServiceProvider.overrideWith((ref) {
        final service = _FakeBatchService(ref, delay: batchDelay);
        onBatch(service);
        return service;
      }),
      mediaLibraryRequestIntervalProvider.overrideWith((ref) => mediaInterval),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  BackgroundTask taskById(ProviderContainer container, String id) {
    return container
        .read(backgroundTaskProvider)
        .firstWhere((task) => task.id == id);
  }

  test('后台任务按顺序执行并同步进度与结果', () async {
    _FakeCompleteService? complete;
    _FakeBatchService? batch;
    final container = makeContainer(
      mediaInterval: const Duration(seconds: 5),
      onComplete: (service) => complete = service,
      onBatch: (service) => batch = service,
    );
    final notifier = container.read(backgroundTaskProvider.notifier);

    final completeId = notifier.startCompleteMissing();
    final batchId = notifier.startBatchCache(
      dimension: BatchCacheDimension.tag,
      name: '测试标签',
    );

    await waitFor(() =>
        taskById(container, completeId).status == BackgroundTaskStatus.running);
    expect(taskById(container, batchId).status, BackgroundTaskStatus.queued);
    expect(taskById(container, completeId).processed, 1);

    await waitFor(() => taskById(container, batchId).isFinished);
    expect(complete!.calls, 1);
    expect(batch!.calls, 1);
    expect(
        taskById(container, completeId).status, BackgroundTaskStatus.completed);
    expect(taskById(container, batchId).status, BackgroundTaskStatus.completed);
    expect(taskById(container, batchId).success, 1);
    expect(complete!.lastRunInterval, const Duration(seconds: 5));
    expect(batch!.lastRunInterval, const Duration(seconds: 5));
  });

  test('可以取消排队任务，不会调用对应服务', () async {
    _FakeCompleteService? complete;
    _FakeBatchService? batch;
    final container = makeContainer(
      completeDelay: const Duration(milliseconds: 30),
      onComplete: (service) => complete = service,
      onBatch: (service) => batch = service,
    );
    final notifier = container.read(backgroundTaskProvider.notifier);

    final firstId = notifier.startCompleteMissing();
    await waitFor(() =>
        taskById(container, firstId).status == BackgroundTaskStatus.running);
    final queuedId = notifier.startBatchCache(
      dimension: BatchCacheDimension.circle,
      name: '测试社团',
    );
    notifier.cancelTask(queuedId);

    await waitFor(() => taskById(container, firstId).isFinished);
    expect(taskById(container, queuedId).status, BackgroundTaskStatus.canceled);
    expect(complete!.calls, 1);
    expect(batch?.calls ?? 0, 0);
  });

  test('取消运行中任务会在当前服务返回后标记为已取消', () async {
    _FakeCompleteService? complete;
    _FakeBatchService? batch;
    final container = makeContainer(
      completeDelay: const Duration(milliseconds: 20),
      onComplete: (service) => complete = service,
      onBatch: (service) => batch = service,
    );
    final notifier = container.read(backgroundTaskProvider.notifier);
    final id = notifier.startCompleteMissing();

    await waitFor(
        () => taskById(container, id).status == BackgroundTaskStatus.running);
    notifier.cancelTask(id);
    await waitFor(() => taskById(container, id).isFinished);

    expect(taskById(container, id).status, BackgroundTaskStatus.canceled);
    expect(taskById(container, id).cancelRequested, true);
    expect(complete!.calls, 1);
    expect(batch?.calls ?? 0, 0);
  });

  test('清除历史任务不会删除仍在运行的任务', () async {
    _FakeCompleteService? complete;
    _FakeBatchService? batch;
    final container = makeContainer(
      batchDelay: const Duration(milliseconds: 20),
      onComplete: (service) => complete = service,
      onBatch: (service) => batch = service,
    );
    final notifier = container.read(backgroundTaskProvider.notifier);
    final id = notifier.startBatchCache(
      dimension: BatchCacheDimension.va,
      name: '测试 CV',
    );

    notifier.clearFinished();
    expect(container.read(backgroundTaskProvider), hasLength(1));
    expect(taskById(container, id).isActive, isTrue);
    notifier.cancelTask(id);
    await waitFor(() => taskById(container, id).isFinished);
    notifier.clearFinished();
    expect(container.read(backgroundTaskProvider), isEmpty);
    expect(complete?.calls ?? 0, 0);
    expect(batch?.calls ?? 0, 1);
  });
}
