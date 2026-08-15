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

/// 单文件多线程下载的可选连接数（分段并发，需服务器支持 Range）。
/// 服务器不支持 Range 或分段下载失败时会自动回退单线程。
const downloadThreadOptions = [1, 2, 4, 8, 16];

/// 当前单文件下载使用的线程数（每段至少 1 MiB，小文件自动用更少线程）
final downloadThreadsProvider = StateProvider<int>((ref) => 4);

/// 文件级并行下载的可选文件数（同一作品内同时下载的文件数）。
const parallelDownloadOptions = [1, 2, 3, 4];

/// 所有文件并发连接数的安全上限：并行文件数 × 每文件线程数不得超过该值。
const maxTotalDownloadConnections = 16;

/// 当前文件级并行数，默认 2；并行时会自动压低单文件线程数。
final parallelDownloadCountProvider = StateProvider<int>((ref) => 2);

/// Debug 模式开关：开启后把日志输出到文件，便于在 Windows 等平台排查问题。
/// 默认 debug 构建关闭、release 构建开启（保持历史行为）。
final debugModeProvider = StateProvider<bool>((ref) => false);

final proxyProvider = StateProvider<String>((ref) => 'DIRECT');

final apiChannelProvider = StateProvider<String>((ref) => 'asmr-200');

/// 批量整理时仅处理未整理过的作品
final onlyOrganizeUnorganizedProvider = StateProvider<bool>((ref) => true);

// ---------- ChickenRice（AI 字幕翻译） ----------

/// ChickenRice 启动脚本（.bat / .cmd）或 infer.exe 的绝对路径。
/// 配置持久化 key 沿用 chickenRiceExePath（向后兼容老配置）。
final chickenRiceScriptPathProvider = StateProvider<String>((ref) => '');

/// 计算设备：auto / cuda / cpu
final chickenRiceDeviceProvider = StateProvider<String>((ref) => 'auto');

/// Whisper 任务：translate（中文）/ transcribe（原文）
final chickenRiceTaskProvider = StateProvider<String>((ref) => 'translate');

/// 下载完成后自动调用 ChickenRice 生成 AI 字幕（带开关）
final autoTranscribeProvider = StateProvider<bool>((ref) => false);

/// 是否已启用 ChickenRice 能力（脚本已配置）
final chickenRiceConfiguredProvider = Provider<bool>(
    (ref) => ref.watch(chickenRiceScriptPathProvider).isNotEmpty);

/// 当前生效的 ChickenRice 配置（聚合）
final chickenRiceConfigProvider = Provider<ChickenRiceConfig>((ref) {
  return ChickenRiceConfig(
    scriptPath: ref.watch(chickenRiceScriptPathProvider),
    device: ref.watch(chickenRiceDeviceProvider),
    task: ref.watch(chickenRiceTaskProvider),
  );
});
