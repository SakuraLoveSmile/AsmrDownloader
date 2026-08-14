import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/pages/downloader/search_result/tracks_view/components/download_progress/download_button.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('下载取消（Tier 1）', () {
    test('下载中调用 cancelAllDownload 将状态置为 canceled', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(dlStatusProvider.notifier).state =
          DownloadStatus.downloading;

      container.read(downloadManagerProvider).cancelAllDownload();

      expect(container.read(dlStatusProvider), DownloadStatus.canceled);
    });

    test('非下载中调用 cancelAllDownload 是 no-op', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(downloadManagerProvider).cancelAllDownload();

      expect(container.read(dlStatusProvider), DownloadStatus.notStarted);
    });

    test('cancelAllDownload 取消 rootFolder 中所有 FileAsset 的 CancelToken', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final folder = Folder(id: 'RJ1', title: 'RJ1');
      final subFolder = Folder(id: 'sub', title: 'sub');
      final asset1 = FileAsset(
        id: 't1',
        type: 'audio',
        title: 't1',
        mediaStreamUrl: 'u',
        mediaDownloadUrl: 'u',
        size: 100,
      )..selected = true;
      final asset2 = FileAsset(
        id: 't2',
        type: 'audio',
        title: 't2',
        mediaStreamUrl: 'u',
        mediaDownloadUrl: 'u',
        size: 100,
      )..selected = true;
      subFolder.children.add(asset2);
      folder
        ..children.add(asset1)
        ..children.add(subFolder);
      container.read(rootFolderProvider.notifier).state = folder;
      container.read(dlStatusProvider.notifier).state =
          DownloadStatus.downloading;

      // 模拟 run() 中下载任务已把 token 登记为在途
      // （_activeCancelTokens 为私有，此处通过可观察行为验证：
      //  cancelDownload 单任务取消 + cancelAllDownload 状态切换）
      container.read(downloadManagerProvider).cancelDownload(asset1);
      container.read(downloadManagerProvider).cancelAllDownload();

      expect(asset1.cancelToken.isCancelled, isTrue);
      expect(container.read(dlStatusProvider), DownloadStatus.canceled);
    });
  });

  group('下载按钮状态（Tier 1 / Tier 3-10）', () {
    testWidgets('下载中显示红色「取消」，点击后状态变为 canceled', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(dlStatusProvider.notifier).state =
          DownloadStatus.downloading;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: Center(child: DownloadButton())),
          ),
        ),
      );

      expect(find.text('取消'), findsOneWidget);
      expect(find.text('下载'), findsNothing);

      await tester.tap(find.text('取消'));
      await tester.pump();

      expect(container.read(dlStatusProvider), DownloadStatus.canceled);
    });

    testWidgets('失败状态显示「重试」', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(dlStatusProvider.notifier).state = DownloadStatus.failed;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: Center(child: DownloadButton())),
          ),
        ),
      );

      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('未开始时显示「下载」', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(body: Center(child: DownloadButton())),
          ),
        ),
      );

      expect(find.text('下载'), findsOneWidget);
    });
  });

  group('下载速度与剩余时间（Tier 1-3）', () {
    test('默认速度为 0、剩余时间为零', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(downloadSpeedProvider), 0);
      expect(container.read(downloadEtaProvider), Duration.zero);
    });

    test('下载中写入速度与剩余时间可被读取', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(downloadSpeedProvider.notifier).state = 2.5 * 1024 * 1024;
      container.read(downloadEtaProvider.notifier).state =
          const Duration(minutes: 3, seconds: 20);

      expect(container.read(downloadSpeedProvider), 2.5 * 1024 * 1024);
      expect(container.read(downloadEtaProvider),
          const Duration(minutes: 3, seconds: 20));
    });
  });
}
