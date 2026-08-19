import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/pages/downloader/search_result/tracks_view/components/download_progress/download_list_panel.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// DownloadListPanel 渲染逻辑的 widget 测试，覆盖规格中的可见性、
/// 自动展开、手动折叠、状态图标、单文件进度与右侧文字等运行时行为。
void main() {
  Widget buildPanel(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: DownloadListPanel(tracksLPadding: 20),
        ),
      ),
    );
  }

  DownloadSegment segment({
    required String title,
    required int size,
    required double fraction,
    required DownloadStatus status,
    double speed = 0,
  }) =>
      DownloadSegment(
        title: title,
        size: size,
        fraction: fraction,
        status: status,
        speed: speed,
      );

  group('DownloadListPanel 可见性（Tier 1）', () {
    testWidgets('段数据为空时不渲染（SizedBox.shrink）', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(buildPanel(container));

      expect(find.text('下载列表'), findsNothing);
    });

    testWidgets('段数据非空时渲染头部行', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(downloadSegmentsProvider.notifier).state = [
        segment(title: 'track1.flac', size: 1024, fraction: 0, status: DownloadStatus.notStarted),
      ];
      container.read(totalTaskCntProvider.notifier).state = 1;

      await tester.pumpWidget(buildPanel(container));

      expect(find.text('下载列表'), findsOneWidget);
    });
  });

  group('DownloadListPanel 折叠与自动展开（Tier 2）', () {
    testWidgets('初始折叠，头部箭头朝下', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(downloadSegmentsProvider.notifier).state = [
        segment(title: 'track1.flac', size: 1024, fraction: 0, status: DownloadStatus.notStarted),
      ];

      await tester.pumpWidget(buildPanel(container));

      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsNothing);
    });

    testWidgets('dlStatus 变为 downloading 时自动展开，箭头切换朝上', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(downloadSegmentsProvider.notifier).state = [
        segment(title: 'track1.flac', size: 1024, fraction: 0, status: DownloadStatus.notStarted),
      ];

      await tester.pumpWidget(buildPanel(container));
      expect(find.byIcon(Icons.expand_more), findsOneWidget);

      container.read(dlStatusProvider.notifier).state = DownloadStatus.downloading;
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.expand_less), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsNothing);
    });

    testWidgets('点击头部行可手动折叠，箭头切回朝下', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(downloadSegmentsProvider.notifier).state = [
        segment(title: 'track1.flac', size: 1024, fraction: 0.5, status: DownloadStatus.downloading),
      ];

      await tester.pumpWidget(buildPanel(container));
      container.read(dlStatusProvider.notifier).state = DownloadStatus.downloading;
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.expand_less), findsOneWidget);

      await tester.tap(find.text('下载列表'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsNothing);
    });
  });

  group('DownloadListPanel 状态图标（Tier 3）', () {
    testWidgets('完成态显示 check_circle 图标', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(downloadSegmentsProvider.notifier).state = [
        segment(title: 'done.flac', size: 1024, fraction: 1, status: DownloadStatus.completed),
      ];
      container.read(dlStatusProvider.notifier).state = DownloadStatus.downloading;

      await tester.pumpWidget(buildPanel(container));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('失败态显示 error 图标', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(downloadSegmentsProvider.notifier).state = [
        segment(title: 'bad.flac', size: 1024, fraction: 0.3, status: DownloadStatus.failed),
      ];
      container.read(dlStatusProvider.notifier).state = DownloadStatus.downloading;

      await tester.pumpWidget(buildPanel(container));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error), findsOneWidget);
    });

    testWidgets('排队态显示 schedule 图标', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(downloadSegmentsProvider.notifier).state = [
        segment(title: 'queue.flac', size: 1024, fraction: 0, status: DownloadStatus.notStarted),
      ];
      container.read(dlStatusProvider.notifier).state = DownloadStatus.downloading;

      await tester.pumpWidget(buildPanel(container));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.schedule), findsOneWidget);
    });

    testWidgets('取消态显示 stop_circle 图标', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(downloadSegmentsProvider.notifier).state = [
        segment(title: 'canceled.flac', size: 1024, fraction: 0, status: DownloadStatus.canceled),
      ];
      container.read(dlStatusProvider.notifier).state = DownloadStatus.downloading;

      await tester.pumpWidget(buildPanel(container));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.stop_circle), findsOneWidget);
    });

    testWidgets('下载中显示 downloading 图标', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(downloadSegmentsProvider.notifier).state = [
        segment(title: 'active.flac', size: 1024, fraction: 0.4, status: DownloadStatus.downloading),
      ];
      container.read(dlStatusProvider.notifier).state = DownloadStatus.downloading;

      await tester.pumpWidget(buildPanel(container));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.downloading), findsOneWidget);
    });
  });

  group('DownloadListPanel 单文件进度与右侧文字（Tier 2-3）', () {
    testWidgets('右侧显示已下载/总大小', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(downloadSegmentsProvider.notifier).state = [
        segment(title: 'a.flac', size: 2048, fraction: 0.5, status: DownloadStatus.downloading),
      ];
      container.read(dlStatusProvider.notifier).state = DownloadStatus.downloading;

      await tester.pumpWidget(buildPanel(container));
      await tester.pumpAndSettle();

      // 0.5 * 2048 = 1024 -> "1.00 KB / 2.00 KB"
      expect(find.text('1.00 KB / 2.00 KB'), findsOneWidget);
    });

    testWidgets('下载中文件额外显示速度', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(downloadSegmentsProvider.notifier).state = [
        segment(
          title: 'a.flac',
          size: 2048,
          fraction: 0.5,
          status: DownloadStatus.downloading,
          speed: 1024,
        ),
      ];
      container.read(dlStatusProvider.notifier).state = DownloadStatus.downloading;

      await tester.pumpWidget(buildPanel(container));
      await tester.pumpAndSettle();

      // "1.00 KB / 2.00 KB · 1.00 KB/s"
      expect(find.text('1.00 KB / 2.00 KB · 1.00 KB/s'), findsOneWidget);
    });

    testWidgets('失败态单文件进度用 error 色', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(downloadSegmentsProvider.notifier).state = [
        segment(title: 'bad.flac', size: 1024, fraction: 0.3, status: DownloadStatus.failed),
      ];
      container.read(dlStatusProvider.notifier).state = DownloadStatus.downloading;

      await tester.pumpWidget(buildPanel(container));
      await tester.pumpAndSettle();

      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.color, Theme.of(tester.element(find.byType(LinearProgressIndicator)))
          .colorScheme
          .error);
    });

    testWidgets('头部显示已完成数/总数', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(downloadSegmentsProvider.notifier).state = [
        segment(title: 'a.flac', size: 1024, fraction: 1, status: DownloadStatus.completed),
        segment(title: 'b.flac', size: 1024, fraction: 0, status: DownloadStatus.notStarted),
      ];
      container.read(currentDlNoProvider.notifier).state = 1;
      container.read(totalTaskCntProvider.notifier).state = 2;

      await tester.pumpWidget(buildPanel(container));

      expect(find.text('1 / 2'), findsOneWidget);
    });
  });

  group('新搜索清空（Tier 2）', () {
    testWidgets('段数据被清空后面板消失', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(downloadSegmentsProvider.notifier).state = [
        segment(title: 'a.flac', size: 1024, fraction: 1, status: DownloadStatus.completed),
      ];
      container.read(dlStatusProvider.notifier).state = DownloadStatus.downloading;

      await tester.pumpWidget(buildPanel(container));
      await tester.pumpAndSettle();
      expect(find.text('下载列表'), findsOneWidget);

      // 模拟 UIService.resetProgress() 清空 segments
      container.read(downloadSegmentsProvider.notifier).state = const [];
      await tester.pumpAndSettle();

      expect(find.text('下载列表'), findsNothing);
    });
  });
}
