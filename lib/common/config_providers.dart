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

/// CV（声优/艺术家）头像目录：即 Navidrome 的 `ArtistImageFolder`。
/// 应用只负责 CV 统计与集中目录式头像的手动管理（复制/清除），
/// 不自动抓取或填充任何头像；Navidrome 侧按提示改两行配置即可生效。
final cvAvatarPathProvider = StateProvider<String>((ref) => '');

/// 媒体库扫描根目录（可包含本机下载目录和已挂载的 SMB/NAS 目录）。
///
/// 扫描器只读取目录名中的 RJ/VJ/BJ 号，不读取音频、字幕或封面明细。
final mediaLibraryRootsProvider =
    StateProvider<List<String>>((ref) => const []);

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

/// GitHub API 认证 token（可选）：更新检查与引擎安装的 API 请求带认证后，
/// 限额从匿名 60 次/小时/IP 提升到 5000 次/小时/账号，
/// 共享代理出口 IP 也不会触发限流。空 = 匿名请求。
final githubTokenProvider = StateProvider<String>((ref) => '');

final apiChannelProvider = StateProvider<String>((ref) => 'asmr-200');

/// 批量整理时仅处理未整理过的作品
final onlyOrganizeUnorganizedProvider = StateProvider<bool>((ref) => true);

/// 批量整理时保留作品内子目录结构（disc1/disc2 等按相对路径原样复制，不扁平化）
final keepOrganizeDirStructureProvider = StateProvider<bool>((ref) => false);

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

/// AI 翻译引擎内置安装目录（用户自选；空 = 未使用内置安装器）
final chickenRiceEngineInstallDirProvider = StateProvider<String>((ref) => '');

/// 内置引擎变体（cu128/gfx110x_all 等；供重装/状态展示）
final chickenRiceEngineVariantProvider = StateProvider<String>((ref) => '');

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

// ---------- 新手引导 ----------

/// 新手引导是否已完成。首次启动时为 false，弹窗完成或跳过后写 true 并持久化，
/// 之后启动不再自动弹出；用户仍可从「下载设置 → 新手引导」手动重新打开。
final onboardingCompletedProvider = StateProvider<bool>((ref) => false);

// ---------- 任务通知与外观 ----------

/// 任务完成（下载/整理/AI字幕/后台任务）是否发送桌面系统通知
final notifyOnCompleteProvider = StateProvider<bool>((ref) => true);

/// 应用外观主题模式：'dark' (深色) / 'light' (浅色) / 'system' (跟随系统)
final themeModeProvider = StateProvider<String>((ref) => 'dark');
