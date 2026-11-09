import 'package:asmr_downloader/services/feedback/feedback_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 用户反馈落盘服务单例（纯 IO，无配置依赖，无需随配置重建）
final feedbackServiceProvider = Provider<FeedbackService>((ref) {
  return FeedbackService();
});
