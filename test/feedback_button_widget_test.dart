import 'package:asmr_downloader/pages/components/app_sidebar.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/feedback_button.dart';
import 'package:asmr_downloader/pages/downloader/settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 反馈入口必须不依赖滚动即可点到：设置面板高于面板可视高度，
/// 放在面板内的入口在默认窗口下会被挤到首屏之外。
void main() {
  testWidgets('侧边栏底部固定显示反馈入口，默认窗口下无需滚动即可点击', (tester) async {
    tester.view.physicalSize = const Size(1040, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: AppSidebar())),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.byType(FeedbackButton);
    expect(button, findsOneWidget);
    expect(button.hitTestable(), findsOneWidget);

    final rect = tester.getRect(button);
    final sidebarRect = tester.getRect(find.byType(AppSidebar));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(sidebarRect.bottom));
  });

  testWidgets('设置面板不再提供重复的反馈入口', (tester) async {
    tester.view.physicalSize = const Size(1040, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const DownloaderSettingsPanel(),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(DownloaderSettingsPanel), findsOneWidget);
    expect(find.byType(FeedbackButton), findsNothing);
  });
}
