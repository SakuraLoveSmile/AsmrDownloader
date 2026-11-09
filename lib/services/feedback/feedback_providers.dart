import 'package:asmr_downloader/services/feedback/feedback_config.dart';
import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 反馈服务身份；[null] 表示当前构建未启用反馈层（debug / 测试默认关闭）。
final feedbackServiceConfigProvider =
    Provider<FeedbackServiceConfig?>((ref) => resolveFeedbackServiceConfig());

/// 根持有的 [FeedbackController]，只在根容器 dispose 时释放。
///
/// 页面与入口只读取并调用它，不创建、也不释放——与灵感球跨页存活、
/// 草稿与登录令牌不因导航丢失的前提一致。
final feedbackControllerProvider = Provider<FeedbackController>((ref) {
  final controller = FeedbackController();
  ref.onDispose(controller.dispose);
  return controller;
});
