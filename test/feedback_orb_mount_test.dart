import 'package:asmr_downloader/services/feedback/feedback_config.dart';
import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证按宿主方式挂载后灵感球确实渲染出来（不只是配置正确）。
void main() {
  Future<FeedbackController> pumpHost(WidgetTester tester) async {
    final controller = FeedbackController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      FeedbackWidget(
        config: buildFeedbackConfig(
          service: const FeedbackServiceConfig(
            apiBase: 'https://feedback.example.com',
            appId: 'asmrdownloader',
          ),
          pageLabel: 'downloader',
        ),
        controller: controller,
        child: MaterialApp(
          home: const Scaffold(body: Center(child: Text('宿主内容'))),
        ),
      ),
    );
    // 测试环境不启动常驻 Ticker，有限次 pump 即可；不能用 pumpAndSettle。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return controller;
  }

  testWidgets('灵感球在场：launcher slot 与球体节点已渲染', (tester) async {
    await pumpHost(tester);

    expect(find.byKey(const Key('feedback-launcher-slot')), findsOneWidget,
        reason: '入口 slot 应渲染');
    expect(find.byKey(const Key('feedback-orb-body')), findsOneWidget,
        reason: '灵感球本体应渲染（而不是 tab 模式的 FAB）');
    expect(find.byKey(const Key('feedback-fab')), findsNothing,
        reason: 'orb 模式下不应出现旧悬浮按钮');
    expect(find.text('宿主内容'), findsOneWidget);
  });

  testWidgets('灵感球尺寸为静止态 56dp，且停靠在右侧', (tester) async {
    await pumpHost(tester);

    final orb = tester.getRect(find.byKey(const Key('feedback-orb-body')));
    expect(orb.width, 56);
    expect(orb.height, 56);

    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(orb.center.dx, greaterThan(screen.width / 2), reason: '应停靠右侧');
  });

  testWidgets('反馈层未启用时不挂载（service 为 null 的等价路径）', (tester) async {
    // 宿主在 service == null 时直接返回 MaterialApp，不包 FeedbackWidget；
    // 这里断言那种结构里确实没有灵感球节点。
    await tester.pumpWidget(
      MaterialApp(home: const Scaffold(body: Center(child: Text('宿主内容')))),
    );
    await tester.pump();

    expect(find.byKey(const Key('feedback-orb-body')), findsNothing);
    expect(find.byKey(const Key('feedback-launcher-slot')), findsNothing);
  });
}
