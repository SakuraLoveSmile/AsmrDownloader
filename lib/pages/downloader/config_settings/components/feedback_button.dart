import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 「反馈」入口按钮：打开 feedback 组件的截图标注 + 文字说明浮层，
/// 提交后由 [UIService.submitFeedback] 落盘到应用数据目录，
/// 供用户作为附件提交到 GitHub Issue。
class FeedbackButton extends ConsumerWidget {
  const FeedbackButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Tooltip(
      message: '截图标注 + 文字说明，保存后可随 GitHub Issue 提交',
      child: OutlinedButton.icon(
        onPressed: () => _showFeedbackSheet(context, ref),
        icon: const Icon(Icons.feedback_outlined, size: 14),
        label: const Text('反馈'),
      ),
    );
  }

  void _showFeedbackSheet(BuildContext context, WidgetRef ref) {
    BetterFeedback.of(context).show(
      (feedback) => ref.read(uiServiceProvider).submitFeedback(feedback),
    );
  }
}
