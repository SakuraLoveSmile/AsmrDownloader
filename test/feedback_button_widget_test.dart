import 'package:asmr_downloader/pages/components/app_sidebar.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/feedback_button.dart';
import 'package:asmr_downloader/services/feedback/feedback_config.dart';
import 'package:asmr_downloader/services/feedback/feedback_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 反馈入口在默认窗口下必须可见可点。
const _service = FeedbackServiceConfig(
  apiBase: 'https://feedback.example.com',
  appId: 'asmrdownloader',
);

void main() {
  testWidgets('侧边栏底部固定显示反馈入口，默认窗口下无需滚动即可点击', (tester) async {
    tester.view.physicalSize = const Size(1040, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          feedbackServiceConfigProvider.overrideWithValue(_service),
        ],
        child: const MaterialApp(home: Scaffold(body: AppSidebar())),
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

  testWidgets('反馈层未启用时侧边栏不显示反馈入口', (tester) async {
    tester.view.physicalSize = const Size(1040, 690);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          feedbackServiceConfigProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(home: Scaffold(body: AppSidebar())),
      ),
    );
    await tester.pumpAndSettle();

    // 按钮自身仍可构建，但渲染为空，避免点开无反应
    expect(find.text('反馈'), findsNothing);
  });
}
