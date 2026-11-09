import 'package:asmr_downloader/services/feedback/feedback_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 「反馈」入口：主动唤起灵感球对应的截图流程（截当前视口 + 打开面板）。
///
/// 灵感球本身就是常驻入口；这里给偏好设置等宿主位置一个等价的显式入口，
/// 两者共用同一个 [FeedbackController]，草稿与登录状态一致。
/// 反馈层未启用（debug / 测试构建）时整块隐藏，避免点开无反应。
class FeedbackButton extends ConsumerWidget {
  const FeedbackButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(feedbackServiceConfigProvider) != null;
    if (!enabled) return const SizedBox.shrink();

    return Tooltip(
      message: '截取当前界面并描述问题，提交到反馈服务',
      child: OutlinedButton.icon(
        onPressed: () => ref.read(feedbackControllerProvider).captureAndOpen(),
        icon: const Icon(Icons.feedback_outlined, size: 14),
        label: const Text('反馈'),
      ),
    );
  }
}
