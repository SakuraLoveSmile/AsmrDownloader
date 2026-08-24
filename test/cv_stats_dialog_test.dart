import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/pages/media_library/components/cv_stats_dialog.dart';
import 'package:asmr_downloader/services/library/cv_stats_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 覆盖 CV 统计对话框所依赖的 provider，使其快速进入「空数据」状态，
/// 便于在不依赖真实媒体库 / 头像目录 / 文件系统的情况下验证布局。
ProviderContainer _buildContainer(String dir) {
  final container = ProviderContainer(overrides: [
    cvAvatarPathProvider.overrideWith((ref) => dir),
    cvStatsProvider.overrideWith((ref) async => <CvStat>[]),
    cvAvatarIndexProvider.overrideWith((ref) async => <String, String>{}),
  ]);
  addTearDown(container.dispose);
  return container;
}

Future<void> _pumpDialog(WidgetTester tester, String dir) async {
  final container = _buildContainer(dir);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => CvStatsDialog(onViewWorks: (_) {}),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('未设置目录：构建无异常并显示占位文案与标题',
      (WidgetTester tester) async {
    await _pumpDialog(tester, '');

    expect(tester.takeException(), isNull);
    expect(find.text('CV 统计与头像管理'), findsOneWidget);
    expect(find.text('尚未设置 CV 头像目录'), findsOneWidget);
    // 目录未设置时「打开目录」按钮应禁用（onPressed 为 null）。
    final openBtn = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '打开目录'),
    );
    expect(openBtn.onPressed, isNull);
  });

  testWidgets('已设置目录：构建无异常并显示目录路径',
      (WidgetTester tester) async {
    const dirPath = '/Volumes/nas/asmr/ArtistImages';
    await _pumpDialog(tester, dirPath);

    expect(tester.takeException(), isNull);
    expect(find.text('CV 统计与头像管理'), findsOneWidget);
    expect(find.text(dirPath), findsOneWidget);
    // 目录已设置时「打开目录」按钮应可用。
    final openBtn = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '打开目录'),
    );
    expect(openBtn.onPressed, isNotNull);
  });
}
