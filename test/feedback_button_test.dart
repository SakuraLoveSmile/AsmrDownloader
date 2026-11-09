import 'package:asmr_downloader/pages/downloader/config_settings/components/feedback_button.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('点击「反馈」打开截图标注浮层，显示中文文案', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: BetterFeedback(
          localeOverride: const Locale('zh'),
          child: const MaterialApp(home: Scaffold(body: FeedbackButton())),
        ),
      ),
    );

    expect(find.text('反馈'), findsOneWidget);

    await tester.tap(find.text('反馈'));
    await tester.pumpAndSettle();

    // 浮层文案来自 feedback 组件的中文翻译，应用锁定中文后应为中文
    expect(find.text('敬请留下您宝贵的意见和建议：'), findsOneWidget);
    expect(find.text('提交'), findsOneWidget);
  });
}
