import 'package:asmr_downloader/services/transcribe/chicken_rice_config.dart';
import 'package:asmr_downloader/utils/json_storage.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

final configFileProvider = Provider<JsonStorage>((ref) {
  return JsonStorage(
    filePath: p.join(getAppDataDir(), 'asmr_dl_config.json'),
  );
});

final downloadPathProvider = StateProvider<String>((ref) => '');

/// Navidrome 媒体库根目录（整理功能的目标路径）
final navidromePathProvider = StateProvider<String>((ref) => '');

/// 下载完成后自动整理到 Navidrome
final autoOrganizeProvider = StateProvider<bool>((ref) => false);

final dlCoverProvider = StateProvider<bool>((ref) => false);

final proxyProvider = StateProvider<String>((ref) => 'DIRECT');

final apiChannelProvider = StateProvider<String>((ref) => 'asmr-200');

/// 批量整理时仅处理未整理过的作品
final onlyOrganizeUnorganizedProvider = StateProvider<bool>((ref) => true);

// ---------- ChickenRice（AI 字幕翻译） ----------

/// infer.exe（或 bat）的绝对路径
final chickenRiceExePathProvider = StateProvider<String>((ref) => '');

/// 计算设备：auto / cuda / cpu
final chickenRiceDeviceProvider = StateProvider<String>((ref) => 'auto');

/// Whisper 任务：translate（中文）/ transcribe（原文）
final chickenRiceTaskProvider = StateProvider<String>((ref) => 'translate');

/// 下载完成后自动调用 ChickenRice 生成 AI 字幕（带开关）
final autoTranscribeProvider = StateProvider<bool>((ref) => false);

/// 是否已启用 ChickenRice 能力（exe 已配置）
final chickenRiceConfiguredProvider =
    Provider<bool>((ref) => ref.watch(chickenRiceExePathProvider).isNotEmpty);

/// 当前生效的 ChickenRice 配置（聚合）
final chickenRiceConfigProvider = Provider<ChickenRiceConfig>((ref) {
  return ChickenRiceConfig(
    exePath: ref.watch(chickenRiceExePathProvider),
    device: ref.watch(chickenRiceDeviceProvider),
    task: ref.watch(chickenRiceTaskProvider),
  );
});
