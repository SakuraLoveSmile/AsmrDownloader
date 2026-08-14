import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/transcribe/chicken_rice_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 结合当前配置构造 ChickenRiceService
final chickenRiceServiceProvider = Provider<ChickenRiceService>((ref) {
  return ChickenRiceService(ref.watch(chickenRiceConfigProvider));
});

/// 字幕转录状态（UI 展示用）
enum TranscribeStatus { idle, running, done, failed }

final transcribeStatusProvider =
    StateProvider<TranscribeStatus>((ref) => TranscribeStatus.idle);

/// 当前转录进度
final transcribeProgressProvider =
    StateProvider<TranscribeProgress?>((ref) => null);

/// 转录已请求取消（true 时服务层 kill 进程）
final transcribeCancelRequestedProvider =
    StateProvider<bool>((ref) => false);
