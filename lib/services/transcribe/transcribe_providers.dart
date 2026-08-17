import 'dart:io';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/transcribe/chicken_rice_service.dart';
import 'package:asmr_downloader/services/transcribe/isolate_process_runner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 结合当前配置构造 ChickenRiceService
final chickenRiceServiceProvider = Provider<ChickenRiceService>((ref) {
  if (!Platform.isWindows) {
    return ChickenRiceService(ref.watch(chickenRiceConfigProvider));
  }
  final runner = IsolateProcessRunner();
  ref.onDispose(() {
    runner.dispose();
  });
  return ChickenRiceService(ref.watch(chickenRiceConfigProvider),
      runner: runner);
});

/// 字幕转录状态（UI 展示用）
enum TranscribeStatus { idle, running, done, failed }

final transcribeStatusProvider =
    StateProvider<TranscribeStatus>((ref) => TranscribeStatus.idle);

/// 当前转录进度
final transcribeProgressProvider =
    StateProvider<TranscribeProgress?>((ref) => null);

/// 转录运行日志（ChickenRice stdout/stderr 逐行，环形缓冲保留最近 N 行）。
/// 直调 infer.exe 后不再有 bat 控制台窗口，输出改由应用内日志弹窗展示。
final transcribeLogLinesProvider =
    StateProvider<List<String>>((ref) => const []);

/// 转录已请求取消（true 时服务层 kill 进程）
final transcribeCancelRequestedProvider = StateProvider<bool>((ref) => false);

/// 正在生成字幕的作品 sourceId（null = 空闲；作品库列表据此显示运行中状态）
final activeTranscribeSourceIdProvider = StateProvider<String?>((ref) => null);
