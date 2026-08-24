import 'dart:io';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/pages/library/tools/engine_setup_dialog.dart';
import 'package:asmr_downloader/pages/update/update_dialog.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/api_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/tracks_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/work_info_providers.dart';
import 'package:asmr_downloader/services/cache/media_library_settings.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/engine/chicken_rice_engine_service.dart';
import 'package:asmr_downloader/services/engine/engine_providers.dart';
import 'package:asmr_downloader/services/library/library_providers.dart';
import 'package:asmr_downloader/services/library/works_library_service.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/organize_service.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:asmr_downloader/services/organize/navidrome_organizer.dart';
import 'package:asmr_downloader/services/transcribe/subtitle_gap_detector.dart';
import 'package:asmr_downloader/services/transcribe/transcribe_providers.dart';
import 'package:asmr_downloader/services/transcribe/vtt_converter.dart';
import 'package:asmr_downloader/services/update/update_providers.dart';
import 'package:asmr_downloader/utils/asmr_url_parser.dart';
import 'package:asmr_downloader/utils/system_proxy_config.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_taskbar/windows_taskbar.dart';

import 'package:path/path.dart' as p;

/// 全局 SnackBar 入口（供无 BuildContext 的下载流程提示）
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// 全局 Navigator 入口（供无 BuildContext 的服务层弹对话框，
/// 如未配置脚本时引导打开 AI 翻译引擎安装向导）
final navigatorKey = GlobalKey<NavigatorState>();

const _defaultSnackBarDuration = Duration(seconds: 3);
const _actionSnackBarDuration = Duration(seconds: 6);

/// 显示一个不会在全局 SnackBar 队列中残留的短提示。
///
/// ScaffoldMessenger 会把连续调用的提示排队；媒体库批量操作和后台任务
/// 容易在短时间内触发多个提示，因此每次显示前清掉旧的当前项和等待项。
void showAppSnackBar(
  BuildContext context,
  String message, {
  SnackBarAction? action,
  Duration? duration,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  _showSnackBar(
    messenger,
    message,
    action: action,
    duration: duration,
  );
}

void _showSnackBar(
  ScaffoldMessengerState messenger,
  String message, {
  SnackBarAction? action,
  Duration? duration,
}) {
  messenger
    ..removeCurrentSnackBar()
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
        duration: duration ??
            (action == null
                ? _defaultSnackBarDuration
                : _actionSnackBarDuration),
      ),
    );
}

class UIService {
  final Ref ref;
  UIService(this.ref);

  Future<void> resetProgress() async {
    ref
      ..read(processProvider.notifier).state = 0
      ..read(currentDlNoProvider.notifier).state = 0
      ..read(totalTaskCntProvider.notifier).state = 0
      ..read(currentFileNameProvider.notifier).state = ''
      ..read(activeFileNamesProvider.notifier).state = const []
      ..read(downloadSpeedProvider.notifier).state = 0
      ..read(downloadEtaProvider.notifier).state = Duration.zero
      ..read(totalBytesProvider.notifier).state = 0
      ..read(downloadedBytesProvider.notifier).state = 0
      ..read(downloadSegmentsProvider.notifier).state = const [];
    if (Platform.isWindows) {
      await WindowsTaskbar.setProgress(0, 0);
    }
  }

  String normalizeInput(String sourceId) {
    return sourceId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
  }

  /// 搜索作品。返回规范化后的 sourceId；空输入/非法输入返回 null。
  /// [silent]=true（启动自动粘贴搜索等场景）时非法输入不弹提示。
  Future<String?> search(String input, {bool silent = false}) async {
    // 空输入静默返回（未输入/剪贴板为空），不弹「无效 sourceId」也不重置进度
    if (input.trim().isEmpty) return null;

    // 下载中搜索（加入队列场景）不清掉进度展示，
    // 否则当前作品的下载进度会被新作品搜索清零。
    if (ref.read(dlStatusProvider) != DownloadStatus.downloading) {
      await resetProgress();
    }

    // 支持直接粘贴 asmr.one 作品页 URL：
    // https://asmr-200.com/work/RJ01619789?path=["RJ01619789","舔耳ONLY音轨"]#work-tree
    // 提取 sourceId 与音轨树目录面包屑（path 参数），
    // work info 获取失败时用作保底音乐标签。
    final urlInfo = parseAsmrWorkUrl(input);
    String searchText;
    if (urlInfo != null) {
      searchText = urlInfo.sourceId;
      ref.read(workTreePathProvider.notifier).state = urlInfo.treePath;
    } else {
      ref.read(workTreePathProvider.notifier).state = const [];
      searchText = normalizeInput(input);
    }
    if (!isSourceIdValid(searchText)) {
      if (!silent) {
        showSnack('无效的 sourceId，请输入 RJ/VJ/BJ 开头加数字，或粘贴 asmr.one 作品页 URL');
      }
      return null;
    }

    if (searchText == ref.read(searchTextProvider)) {
      // force to refetch
      ref
        ..invalidate(workInfoProvider)
        ..invalidate(rawTracksProvider)
        ..invalidate(coverBytesProvider);
    } else {
      ref.read(searchTextProvider.notifier).state = searchText;
    }
    return searchText;
  }

  /// 从剪贴板粘贴并搜索；[silent] 透传给 [search]（启动自动搜索用）。
  Future<String?> pasteAndSearch({bool silent = false}) async {
    final clipBoardText = (await Clipboard.getData('text/plain'))?.text;
    if (clipBoardText == null) return null;

    // 注意：不再把旧 sourceId 写回剪贴板，避免覆盖用户剪贴板中的其他内容
    return search(clipBoardText, silent: silent);
  }

  void onApiChannelChoosed(String? newValue) {
    if (newValue == null || newValue == ref.read(apiChannelProvider)) return;

    ref
      ..read(apiChannelProvider.notifier).state = newValue
      ..read(configFileProvider).addOrUpdate({'apiChannel': newValue})
      ..read(asmrApiProvider).setApiChannel(newValue);
  }

  Future<void> onProxyChanged(bool? value) async {
    if (value == null) return;

    final proxy = value ? SystemProxyConfig.systemProxy : 'DIRECT';

    if (proxy == ref.read(proxyProvider)) return;

    ref
      ..read(proxyProvider.notifier).state = proxy
      ..read(configFileProvider).addOrUpdate({'proxy': proxy})
      ..read(asmrApiProvider).proxy = proxy;
  }

  /// 保存 GitHub Token（空 = 清除）：持久化到配置，服务 provider
  /// watch githubTokenProvider 后自动重建生效
  void setGithubToken(String token) {
    final t = token.trim();
    if (t == ref.read(githubTokenProvider)) return;

    ref.read(githubTokenProvider.notifier).state = t;
    ref.read(configFileProvider).addOrUpdate({'githubToken': t}).catchError(
        (e) => showSnack('配置保存失败，重启后可能丢失：$e'));
    Log.info('github token ${t.isEmpty ? 'cleared' : 'updated'}');
    showSnack(t.isEmpty ? 'GitHub Token 已清除' : 'GitHub Token 已保存');
  }

  void onDlCoverChanged(bool? value) {
    if (value == null) return;

    ref
      ..read(dlCoverProvider.notifier).state = value
      ..read(configFileProvider).addOrUpdate({'dlCover': value});
    Log.info('dlCover: $value');
  }

  void onDownloadThreadsChanged(int? value) {
    if (value == null || value == ref.read(downloadThreadsProvider)) return;

    ref
      ..read(downloadThreadsProvider.notifier).state = value
      ..read(configFileProvider).addOrUpdate({'downloadThreads': value});
    Log.info('downloadThreads: $value');
  }

  void onDebugModeChanged(bool? value) {
    if (value == null || value == ref.read(debugModeProvider)) return;

    ref
      ..read(debugModeProvider.notifier).state = value
      ..read(configFileProvider).addOrUpdate({'debugMode': value});
    Log.setFileOutputEnabled(value);
    Log.info('debugMode: $value');
  }

  void onAutoUpdateCheckChanged(bool? value) {
    if (value == null || value == ref.read(autoCheckUpdateProvider)) return;

    ref
      ..read(autoCheckUpdateProvider.notifier).state = value
      ..read(configFileProvider).addOrUpdate({'autoCheckUpdate': value});
    // 联动周期复查定时器：开启即复查、关闭即停止，设置变更即时生效。
    final notifier = ref.read(latestUpdateProvider.notifier);
    if (value) {
      notifier.startPeriodicCheck();
    } else {
      notifier.stopPeriodicCheck();
    }
    Log.info('autoCheckUpdate: $value');
  }

  void onParallelDownloadCountChanged(int? value) {
    if (value == null || value == ref.read(parallelDownloadCountProvider)) {
      return;
    }

    ref
      ..read(parallelDownloadCountProvider.notifier).state = value
      ..read(configFileProvider).addOrUpdate({'parallelDownloadCount': value});
    Log.info('parallelDownloadCount: $value');
  }

  /// 保存媒体库后台网络任务的统一请求间隔。
  void onMediaLibraryRequestIntervalChanged(Duration? value) {
    if (value == null ||
        !mediaLibraryRequestIntervalOptions.contains(value) ||
        value == ref.read(mediaLibraryRequestIntervalProvider)) {
      return;
    }

    ref.read(mediaLibraryRequestIntervalProvider.notifier).state = value;
    ref.read(configFileProvider).addOrUpdate({
      'mediaLibraryRequestIntervalMs': value.inMilliseconds
    }).catchError((error) => showSnack('媒体库设置保存失败，重启后可能丢失：$error'));
    Log.info('mediaLibraryRequestInterval: ${value.inMilliseconds}ms');
  }

  void onAutoOrganizeChanged(bool? value) {
    if (value == null) return;

    ref
      ..read(autoOrganizeProvider.notifier).state = value
      ..read(configFileProvider).addOrUpdate({'autoOrganize': value});
    Log.info('autoOrganize: $value');
  }

  // ---------- ChickenRice（AI 字幕翻译） ----------

  /// 下载完成后自动翻译开关
  void onAutoTranscribeChanged(bool? value) {
    if (value == null) return;
    ref
      ..read(autoTranscribeProvider.notifier).state = value
      ..read(configFileProvider).addOrUpdate({'autoTranscribe': value});
    Log.info('autoTranscribe: $value');
  }

  /// 设置 ChickenRice 脚本路径（.bat/.cmd/infer.exe；手动输入/选择）
  void setChickenRiceScriptPath(String path) {
    ref.read(chickenRiceScriptPathProvider.notifier).state = path;
    ref
        .read(configFileProvider)
        .addOrUpdate({'chickenRiceExePath': path}).catchError(
            (e) => showSnack('配置保存失败，重启后可能丢失：$e'));
    Log.info('chickenRiceScriptPath: $path');
    showSnack('已选择脚本：$path');
  }

  /// 通过文件选择器选取 ChickenRice 脚本（.bat/.cmd）或 infer.exe
  Future<void> pickChickenRiceScript() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['bat', 'cmd', 'exe'],
    );
    final files = result?.files;
    if (files == null || files.isEmpty) return;
    final path = files.first.path;
    if (path == null) return;
    setChickenRiceScriptPath(path);
  }

  /// 设置计算设备（auto/cuda/cpu）
  void setChickenRiceDevice(String device) {
    ref
      ..read(chickenRiceDeviceProvider.notifier).state = device
      ..read(configFileProvider).addOrUpdate({'chickenRiceDevice': device});
  }

  /// 设置任务（translate/transcribe）
  void setChickenRiceTask(String task) {
    ref
      ..read(chickenRiceTaskProvider.notifier).state = task
      ..read(configFileProvider).addOrUpdate({'chickenRiceTask': task});
  }

  /// 请求取消正在进行的转录
  void cancelTranscribe() {
    ref.read(transcribeCancelRequestedProvider.notifier).state = true;
  }

  // ---------- AI 翻译引擎内置安装器 ----------

  /// 设置引擎安装目录（持久化）
  void setChickenRiceEngineInstallDir(String dir) {
    ref.read(chickenRiceEngineInstallDirProvider.notifier).state = dir;
    ref
        .read(configFileProvider)
        .addOrUpdate({'chickenRiceEngineInstallDir': dir}).catchError(
            (e) => showSnack('配置保存失败，重启后可能丢失：$e'));
  }

  /// 执行引擎安装（安装向导调用）；成功返回 infer.exe 路径并自动配置。
  ///
  /// 安装成功后：scriptPath 自动指向组件内 infer.exe，设备预置 cuda；
  /// 现有的直调 exe 链路（进度/日志/lrc-only/缺口清单）无缝复用。
  Future<String?> installEngine({
    required String installDir,
    required String variant,
    required String task,
  }) async {
    final svc = ref.read(chickenRiceEngineServiceProvider);
    final exePath = await svc.install(
      installDir: installDir,
      variant: variant,
      task: task,
      onState: (s) {
        ref.read(engineInstallStateProvider.notifier).state = s;
      },
    );
    if (exePath != null) {
      setChickenRiceEngineInstallDir(installDir);
      ref
        ..read(chickenRiceEngineVariantProvider.notifier).state = variant
        ..read(configFileProvider)
            .addOrUpdate({'chickenRiceEngineVariant': variant});
      setChickenRiceScriptPath(exePath);
      setChickenRiceDevice('cuda');
      showSnack('AI 翻译引擎安装完成');
    }
    return exePath;
  }

  /// 请求取消进行中的引擎安装
  void cancelEngineInstall() {
    ref.read(chickenRiceEngineServiceProvider).requestCancel();
  }

  /// 探测内置引擎完整性（安装目录内的 infer.exe/models）
  Future<EngineProbeResult> probeEngine() {
    return ref
        .read(chickenRiceEngineServiceProvider)
        .probe(ref.read(chickenRiceEngineInstallDirProvider));
  }

  /// 把 ChickenRice 配置指向安装目录内已装好的引擎（自动检测用）。
  /// 仅当引擎完整（exe + VAD + 主模型都在）时才启用；设备为默认
  /// auto 时按安装语义预置 cuda。成功返回 exe 路径，否则 null。
  Future<String?> linkInstalledEngine({String? installDir}) async {
    final String dir =
        installDir ?? ref.read(chickenRiceEngineInstallDirProvider);
    final probe = await ref.read(chickenRiceEngineServiceProvider).probe(dir);
    if (!probe.installed || !probe.modelsReady || probe.exePath == null) {
      return null;
    }
    if (dir != ref.read(chickenRiceEngineInstallDirProvider)) {
      setChickenRiceEngineInstallDir(dir);
    }
    setChickenRiceScriptPath(probe.exePath!);
    if (ref.read(chickenRiceDeviceProvider) == 'auto') {
      setChickenRiceDevice('cuda');
    }
    Log.info('linked installed engine: ${probe.exePath}');
    return probe.exePath;
  }

  /// 启动自动检测：配置的脚本路径缺失/失效，但内置安装目录内的引擎
  /// 完整时自动关联启用，避免用户已安装过引擎还要重新手动选择。
  Future<void> autoLinkInstalledEngine() async {
    final configured = ref.read(chickenRiceScriptPathProvider);
    if (configured.isNotEmpty && File(configured).existsSync()) return;
    if (ref.read(chickenRiceEngineInstallDirProvider).isEmpty) return;
    await linkInstalledEngine();
  }

  /// 运行日志环形缓冲上限（供日志弹窗实时展示，超出丢弃最旧）
  static const int _kTranscribeLogCap = 300;

  /// ChickenRice 输出逐行写入日志缓冲（UI 实时展示）
  void _appendTranscribeLog(String line) {
    final notifier = ref.read(transcribeLogLinesProvider.notifier);
    final lines = [...notifier.state, line];
    notifier.state = lines.length > _kTranscribeLogCap
        ? lines.sublist(lines.length - _kTranscribeLogCap)
        : lines;
  }

  /// 对指定作品执行 ChickenRice 字幕翻译。
  /// 返回 true 表示已启动/完成；false 表示未执行（脚本未配置/正在运行/无字幕缺口）。
  /// [pickScriptIfEmpty] 为 true 且未配置脚本时弹出文件选择器引导选择。
  Future<bool> transcribeWork(
    String sourceId,
    String sourceDir, {
    bool pickScriptIfEmpty = false,
  }) {
    return transcribeWorks(
      [(sourceId: sourceId, sourceDir: sourceDir)],
      pickScriptIfEmpty: pickScriptIfEmpty,
    );
  }

  /// 对多个作品批量执行 ChickenRice 字幕翻译。
  ///
  /// 关键优化：聚合所有作品的「缺字幕目录」为**一次进程调用**
  /// （`run(dirs: [...])`），Whisper 模型只加载一次；进度为跨作品的
  /// 总进度（ChickenRice 对全部 base_dirs 统一扫描、统一 n/total）。
  /// 每个作品先做缺口过滤：目录不存在或所有音轨已有字幕的作品
  /// 不会传给 ChickenRice，避免空跑。
  Future<bool> transcribeWorks(
    List<({String sourceId, String sourceDir})> works, {
    bool pickScriptIfEmpty = false,
  }) async {
    if (works.isEmpty) return false;
    if (!ref.read(chickenRiceConfigProvider).isConfigured) {
      if (!pickScriptIfEmpty) {
        showSnack('未配置 ChickenRice 启动脚本');
        return false;
      }
      // 引导入口：优先弹内置安装向导（一键安装引擎）；
      // 无可用 Navigator 时回退手动选择脚本。
      final nav = navigatorKey.currentState;
      if (nav != null && nav.context.mounted) {
        await showEngineSetupDialog(nav.context);
      } else {
        await pickChickenRiceScript();
      }
      if (!ref.read(chickenRiceConfigProvider).isConfigured) return false;
    }
    final probe = ref.read(chickenRiceServiceProvider).probeScript();
    if (probe != null) {
      showSnack('ChickenRice 不可用：$probe');
      return false;
    }
    if (ref.read(transcribeStatusProvider) == TranscribeStatus.running) {
      showSnack('字幕翻译正在进行中');
      return false;
    }

    // 先切运行态（指示器立即显示「启动中…」、取消可用），再异步扫描
    // 字幕缺口 —— 扫描放最后才做，避免多作品目录同步遍历卡死主线程，
    // 表现为点击后无响应几秒才开始翻译。
    ref
      ..read(activeTranscribeSourceIdProvider.notifier).state =
          works.first.sourceId
      ..read(transcribeStatusProvider.notifier).state = TranscribeStatus.running
      ..read(transcribeProgressProvider.notifier).state = null
      ..read(transcribeLogLinesProvider.notifier).state = const []
      ..read(transcribeCancelRequestedProvider.notifier).state = false;
    _appendTranscribeLog('扫描字幕缺口…');

    // 预判：聚合每个作品的缺口目录；无缺口/目录缺失的作品跳过
    final targets = <String>[];
    var noGap = 0;
    var notExist = 0;
    for (final w in works) {
      if (!await Directory(w.sourceDir).exists()) {
        notExist++;
        continue;
      }
      final missing =
          await SubtitleGapDetector.findMissingSubtitleTracksAsync(w.sourceDir);
      if (missing.isEmpty) {
        noGap++;
        continue;
      }
      // 传「缺字幕的音轨文件」而非整个作品目录：ChickenRice 自身的跳过
      // 判据只认 foo.lrc（纯 stem），不认官方字幕的 foo.mp3.vtt 命名，
      // 传目录会把已有官方字幕的音轨也重复翻译。改传文件清单后以本应用
      // 的判据为准，只翻真正缺字幕的音轨。
      targets.addAll(missing.map((f) => f.path));
    }
    if (targets.isEmpty) {
      // 无缺口：退回空闲并清掉扫描日志，避免留下孤立的「扫描字幕缺口…」
      ref
        ..read(transcribeStatusProvider.notifier).state = TranscribeStatus.idle
        ..read(activeTranscribeSourceIdProvider.notifier).state = null
        ..read(transcribeLogLinesProvider.notifier).state = const [];
      showSnack(
          works.length == 1 ? '所有音轨已有字幕，无需 AI 翻译' : '所选作品音轨均已有字幕，无需 AI 翻译');
      return false;
    }
    Log.info('transcribeWorks: ${works.length} works -> ${targets.length} '
        'missing tracks (noGap=$noGap, notExist=$notExist)');
    _appendTranscribeLog('正在启动翻译引擎（杀毒软件首次扫描可能耗时较长）…');

    final result = await ref.read(chickenRiceServiceProvider).run(
          dirs: targets,
          onProgress: (progress) {
            ref.read(transcribeProgressProvider.notifier).state = progress;
          },
          onOutput: _appendTranscribeLog,
          isCancelled: () => ref.read(transcribeCancelRequestedProvider),
        );
    final completed = result.success;

    ref
      ..read(transcribeStatusProvider.notifier).state =
          completed ? TranscribeStatus.done : TranscribeStatus.failed
      ..read(transcribeCancelRequestedProvider.notifier).state = false
      ..read(activeTranscribeSourceIdProvider.notifier).state = null;
    // 假成功检测：退出码 0 但 ChickenRice 明确「未找到要处理的文件」
    // （多为音频后缀/格式不匹配），给出可操作的提示而不是「完成」。
    final skipped = noGap + notExist;
    showSnack(
      !completed
          ? '字幕翻译失败或已取消'
          : (result.filesProcessed == 0
              ? '未找到需要处理的文件（请检查音频格式配置）'
              : (skipped > 0 ? '字幕翻译完成（跳过 $skipped 个已有字幕/无效的作品）' : '字幕翻译完成')),
    );
    ref.invalidate(worksLibraryProvider);
    return completed;
  }

  /// 供「下载完成自动翻译」调用的非 UI 版本（无上下文提示直接执行）。
  /// 目录优先从注册表取（下载完成已 upsert），兜底按当前搜索上下文计算。
  Future<bool> autoTranscribe(String sourceId) async {
    final cfg = ref.read(chickenRiceConfigProvider);
    if (!cfg.isConfigured) return false;
    // 互斥：已有手动/自动翻译在跑时跳过，避免并发启动多个 infer.exe
    // （模型重复加载、显存/算力争抢、状态互相覆盖）。
    if (ref.read(transcribeStatusProvider) == TranscribeStatus.running) {
      Log.info(
          'chickenRice autoTranscribe skipped: run in progress: $sourceId');
      return false;
    }
    final probe = ref.read(chickenRiceServiceProvider).probeScript();
    if (probe != null) {
      Log.warning('chickenRice autoTranscribe skipped: $probe');
      return false;
    }

    String? sourceDir;
    final entry = await ref.read(worksIndexProvider).get(sourceId);
    if (entry != null && Directory(entry.sourceDir).existsSync()) {
      sourceDir = entry.sourceDir;
    } else {
      final fallback = p.join(ref.read(voiceWorkPathProvider), sourceId);
      if (Directory(fallback).existsSync()) sourceDir = fallback;
    }
    if (sourceDir == null) {
      Log.warning('chickenRice autoTranscribe skipped: dir missing: $sourceId');
      return false;
    }

    ref
      ..read(activeTranscribeSourceIdProvider.notifier).state = sourceId
      ..read(transcribeStatusProvider.notifier).state = TranscribeStatus.running
      ..read(transcribeProgressProvider.notifier).state = null
      ..read(transcribeLogLinesProvider.notifier).state = const []
      ..read(transcribeCancelRequestedProvider.notifier).state = false;
    _appendTranscribeLog('正在启动翻译引擎（杀毒软件首次扫描可能耗时较长）…');

    final result = await ref.read(chickenRiceServiceProvider).runOnDir(
          sourceDir,
          onProgress: (progress) {
            ref.read(transcribeProgressProvider.notifier).state = progress;
          },
          onOutput: _appendTranscribeLog,
          isCancelled: () => ref.read(transcribeCancelRequestedProvider),
        );
    final completed = result.success;
    if (completed && result.filesProcessed == 0) {
      Log.warning('chickenRice autoTranscribe: no files processed: $sourceId');
    }
    ref
      ..read(transcribeStatusProvider.notifier).state =
          completed ? TranscribeStatus.done : TranscribeStatus.failed
      ..read(transcribeCancelRequestedProvider.notifier).state = false
      ..read(activeTranscribeSourceIdProvider.notifier).state = null;
    ref.invalidate(worksLibraryProvider);
    return completed;
  }

  Future<void> pickDlPath() async {
    final dlPath = await FilePicker.platform.getDirectoryPath();
    if (dlPath == null) return;

    ref
      ..read(downloadPathProvider.notifier).state = dlPath
      ..read(configFileProvider).addOrUpdate({'dlPath': dlPath});
    _addMediaLibraryRoot(dlPath);
    Log.info('dlPath: $dlPath');
    showSnack('下载路径已设置为 $dlPath');
  }

  Future<void> pickNavidromePath() async {
    final navidromePath = await FilePicker.platform.getDirectoryPath();
    if (navidromePath == null) return;

    ref
      ..read(navidromePathProvider.notifier).state = navidromePath
      ..read(configFileProvider).addOrUpdate({'navidromePath': navidromePath});
    _addMediaLibraryRoot(navidromePath);
    Log.info('navidromePath: $navidromePath');
    showSnack('整理路径已设置为 $navidromePath');
  }

  Future<void> pickCvAvatarPath() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return;

    ref
      ..read(cvAvatarPathProvider.notifier).state = path
      ..read(configFileProvider).addOrUpdate({'cvAvatarPath': path});
    Log.info('cvAvatarPath: $path');
    showSnack('CV 头像目录已设置为 $path');
  }

  /// 下载/整理路径变更后自动加入轻量媒体库扫描根目录。
  /// 用户仍可在媒体库设置中移除不想扫描的目录。
  void _addMediaLibraryRoot(String path) {
    final normalized = p.normalize(path.trim());
    if (normalized.isEmpty) return;
    final roots = [...ref.read(mediaLibraryRootsProvider)];
    if (roots.any((root) => p.equals(p.normalize(root), normalized))) return;
    roots.add(normalized);
    ref
      ..read(mediaLibraryRootsProvider.notifier).state = roots
      ..read(configFileProvider).addOrUpdate({'mediaLibraryRoots': roots});
  }

  /// 执行整理（不依赖 UI），返回整理结果；未执行成功返回 null
  /// [pickPathIfEmpty] 整理路径未设置时是否弹目录选择器（手动整理时 true，自动整理时 false）
  Future<OrganizeResult?> organizeCurrentWork(
      {bool pickPathIfEmpty = false}) async {
    var navidromePath = ref.read(navidromePathProvider);
    if (navidromePath.isEmpty) {
      if (!pickPathIfEmpty) {
        Log.warning('organize skipped: navidromePath not set');
        return null;
      }
      await pickNavidromePath();
      navidromePath = ref.read(navidromePathProvider);
      if (navidromePath.isEmpty) return null;
    }

    final sourceId = ref.read(sourceIdProvider);
    if (sourceId == null) return null;

    final sourceDir = p.join(ref.read(voiceWorkPathProvider), sourceId);
    if (!Directory(sourceDir).existsSync()) return null;

    // 复用封面下载功能获取封面字节（不依赖本地 *_cover.jpg 文件）
    Uint8List? coverBytes;
    final coverAsync = ref.read(coverBytesProvider);
    if (coverAsync is AsyncData && coverAsync.value != null) {
      coverBytes = coverAsync.value;
    } else {
      final coverUrl = ref.read(coverUrlProvider);
      if (coverUrl.isNotEmpty) {
        coverBytes = await ref.read(asmrApiProvider).getCoverBytes(coverUrl);
      }
    }

    // 走统一整理编排层（手动/自动/批量共用），含汉化 circle 跟踪与 artist 保底
    final workInfo = ref.read(workInfoProvider).value;
    final cvNames = ref.read(cvLsProvider).join('&');
    // 社团名已解析为原始社团名（汉化版跟踪原版），整理与注册表共用同一值
    final circleName = await ref.read(circleNameProvider.future);
    final result = await ref.read(organizeServiceProvider).organizeWork(
          sourceId: sourceId,
          sourceDir: sourceDir,
          targetRoot: navidromePath,
          workInfo: workInfo,
          fallbackTitle: ref.read(titleProvider),
          fallbackCvNames: cvNames,
          fallbackCircle: circleName,
          coverBytes: coverBytes,
        );

    // 补录注册表（含整理时间），批量整理依赖它
    if (result != null) {
      await ref.read(worksIndexProvider).upsert(WorkEntry(
            sourceId: sourceId,
            dlPath: ref.read(downloadPathProvider),
            dirName: p.basename(ref.read(voiceWorkPathProvider)),
            title: ref.read(titleProvider),
            cvNames: cvNames,
            circleName: circleName,
            releaseDate: ref.read(releaseDateProvider),
            tags: ref.read(tagLsProvider),
            coverUrl: ref.read(coverUrlProvider),
            organizedAt: DateTime.now().toIso8601String(),
          ));
      ref.invalidate(worksLibraryProvider);
      ref.invalidate(unorganizedCountProvider);
    }

    return result;
  }

  /// 对作品库中的单个作品执行整理（离线优先：注册表元数据 → 目录名解析）。
  /// [pickPathIfEmpty] 整理路径未设置时是否弹目录选择器。
  /// 返回整理 outcome；未执行成功返回 null。
  Future<OrganizeEntryOutcome?> organizeWorkFor(
    WorksListItem item, {
    bool pickPathIfEmpty = false,
  }) async {
    showSnack('正在整理 ${item.sourceId}…');

    var navidromePath = ref.read(navidromePathProvider);
    if (navidromePath.isEmpty) {
      if (!pickPathIfEmpty) {
        Log.warning('organize skipped: navidromePath not set');
        return null;
      }
      await pickNavidromePath();
      navidromePath = ref.read(navidromePathProvider);
      if (navidromePath.isEmpty) return null;
    }

    final entry = WorkEntry(
      sourceId: item.sourceId,
      dlPath: item.dlPath,
      dirName: item.dirName,
      title: item.title,
      cvNames: item.cvNames,
      circleName: item.circleName,
    );
    final organizer = ref.read(organizeServiceProvider);
    if (await organizer.needsWorkInfoNetwork(entry, fetchWorkInfo: true)) {
      showSnack('正在整理 ${item.sourceId}…需联网获取元数据，最长约 17 秒…');
    }
    final outcome = await organizer.organizeEntry(
      entry,
      targetRoot: navidromePath,
      fetchWorkInfo: true,
    );
    if (outcome.result != null) {
      // 补录整理时间（含解析后的元数据回写）
      await ref.read(worksIndexProvider).upsert(outcome.resolvedEntry
          .copyWith(organizedAt: DateTime.now().toIso8601String()));
    }
    ref.invalidate(worksLibraryProvider);
    ref.invalidate(unorganizedCountProvider);
    return outcome;
  }

  /// 下载完成后的自动整理（路径未设置时弹目录选择器）
  Future<void> autoOrganize() async {
    final result = await organizeCurrentWork(pickPathIfEmpty: true);

    if (result == null) {
      showSnack('自动整理未执行：未设置整理路径或作品未下载');
      return;
    }
    var msg = '自动整理完成：复制 ${result.copied} 个文件，跳过 ${result.skipped} 个';
    if (result.tagWriteFailures > 0) {
      msg += '，${result.tagWriteFailures} 个文件标签写入失败';
    }
    showSnack(msg);
  }

  /// 弹出用户可见的提示（无 BuildContext 时走全局 scaffoldMessengerKey）。
  /// 纯逻辑调用（下载流程/单元测试）可能没有可用的 messenger，静默跳过。
  void showSnack(
    String message, {
    BuildContext? context,
    SnackBarAction? action,
    Duration? duration,
  }) {
    ScaffoldMessengerState? messenger;
    if (context != null) {
      messenger = ScaffoldMessenger.maybeOf(context);
    } else {
      try {
        messenger = scaffoldMessengerKey.currentState;
      } catch (_) {
        // WidgetsBinding 未初始化（如单元测试环境），跳过
        return;
      }
    }
    if (messenger == null) return;
    _showSnackBar(messenger, message, action: action, duration: duration);
  }

  /// SnackBar「手动检查」按钮回调：触发手动检查，发现新版则弹更新对话框。
  Future<void> manualCheckFromSnack() async {
    final hasNew = await ref.read(latestUpdateProvider.notifier).manualCheck();
    if (!hasNew) return;
    final nav = navigatorKey.currentState;
    if (nav != null && nav.mounted) {
      await showUpdateDialog(nav.context);
    }
  }

  void openFolder() {
    final vkSourceIdPath =
        p.join(ref.read(voiceWorkPathProvider), ref.read(sourceIdProvider));
    openFolderForDir(vkSourceIdPath);
  }

  /// 在系统文件管理器中打开指定目录（不存在时回退到下载根目录）。
  void openFolderForDir(String path) {
    final dir =
        Directory(path).existsSync() ? path : ref.read(downloadPathProvider);

    if (Platform.isWindows) {
      Process.run('explorer "$dir"', []);
    } else {
      Process.run('open', [dir]);
    }
    Log.info('open folder: "$dir"');
  }

  /// 把作品目录内的 .vtt 字幕批量转换为同名 .lrc（跳过已有 .lrc）。
  /// 返回转换数量。
  Future<int> convertVttToLrcForWork(String sourceDir) async {
    final count = await VttConverter.convertAll(sourceDir);
    showSnack(count == 0 ? '没有可转换的 vtt 字幕' : '已转换 $count 个字幕为 lrc');
    ref.invalidate(worksLibraryProvider);
    return count;
  }

  Future<void> onExit(BuildContext context) async {
    if (DownloadStatus.downloading == ref.read(dlStatusProvider)) {
      await windowManager.show();
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('文件下载中'),
              content: const Text('你确定要关闭吗？下载将被取消，再次下载会继承已下载的部分。'),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    // 不要用windowManager.destroy()，有明显的卡顿
                    windowManager
                      ..setPreventClose(false)
                      ..close();
                  },
                  child: const Text('关闭'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ],
            );
          },
        );
      }
    } else {
      windowManager
        ..setPreventClose(false)
        ..close();
    }
  }
}
