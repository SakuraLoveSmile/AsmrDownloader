import 'dart:async';
import 'dart:io';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/common/const.dart';
import 'package:asmr_downloader/pages/onboarding/onboarding_controller.dart';
import 'package:asmr_downloader/pages/update/update_dialog.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/api_providers.dart';
import 'package:asmr_downloader/services/cache/media_library_settings.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:asmr_downloader/services/ui/ui_service.dart';
import 'package:asmr_downloader/services/update/update_providers.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:asmr_downloader/utils/system_proxy_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

class Initialization extends ConsumerStatefulWidget {
  const Initialization({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<Initialization> createState() => _InitializationState();
}

class _InitializationState extends ConsumerState<Initialization> {
  @override
  void initState() {
    super.initState();
    // init
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // startup search：剪贴板里有 RJ 号时自动搜索；
      // 剪贴板为普通文本/空时静默忽略，不弹「无效 sourceId」
      await Future.delayed(const Duration(milliseconds: PASTE_SEARCH_DELAY_MS));
      ref.read(uiServiceProvider).pasteAndSearch(silent: true);
    });
  }

  @override
  void dispose() {
    // dispose
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(_initProvider);

    if (result.isLoading) {
      return const Center(
        child: SizedBox(
          width: 50.0,
          height: 50.0,
          child: CircularProgressIndicator(),
        ),
      );
    } else if (result.hasError) {
      return const Text('Error initializing');
    }

    return widget.child;
  }
}

final _initProvider = FutureProvider.autoDispose((ref) async {
  final config = await ref.read(configFileProvider).read();

  // api channel and proxy

  ref.read(apiChannelProvider.notifier).state =
      config['apiChannel'] as String? ?? 'asmr-200';

  final savedProxy = config['proxy'] as String? ?? 'DIRECT';
  if (savedProxy != 'DIRECT') {
    final proxy = SystemProxyConfig.systemProxy;
    ref.read(proxyProvider.notifier).state = proxy;
    ref.read(configFileProvider).addOrUpdate({'proxy': proxy});
  }

  ref.read(asmrApiProvider)
    ..setApiChannel(ref.read(apiChannelProvider))
    ..proxy = ref.read(proxyProvider);

  // misc

  // macOS 默认下载到 ~/Downloads；Windows 保持应用目录（相对路径）
  var savedDlPath = config['dlPath'] as String? ?? '';
  if (savedDlPath.isEmpty && Platform.isMacOS) {
    final downloadsDir = await getDownloadsDirectory();
    savedDlPath = downloadsDir?.path ?? '';
  }
  ref.read(downloadPathProvider.notifier).state = savedDlPath;
  final savedNavidromePath = config['navidromePath'] as String? ?? '';
  ref.read(navidromePathProvider.notifier).state = savedNavidromePath;
  final savedCvAvatarPath = config['cvAvatarPath'] as String? ?? '';
  ref.read(cvAvatarPathProvider.notifier).state = savedCvAvatarPath;

  // 媒体库默认沿用下载目录和整理目录；用户一旦在媒体库设置中保存过
  // 自定义列表，就只使用自定义列表。这样 NAS 可以直接作为第二个扫描根目录。
  final hasConfiguredMediaRoots = config.containsKey('mediaLibraryRoots');
  final configuredMediaRoots = (config['mediaLibraryRoots'] as List?)
          ?.map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList() ??
      const <String>[];
  final mediaRoots = hasConfiguredMediaRoots
      ? configuredMediaRoots
      : <String>{savedDlPath, savedNavidromePath}
          .where((value) => value.isNotEmpty)
          .toList();
  ref.read(mediaLibraryRootsProvider.notifier).state = mediaRoots;
  ref.read(dlCoverProvider.notifier).state =
      config['dlCover'] as bool? ?? false;

  // 媒体库后台网络任务统一请求间隔：只接受设置页提供的选项，
  // 非法或旧配置回退到默认 2 秒。
  final savedMediaIntervalMs =
      (config['mediaLibraryRequestIntervalMs'] as num?)?.toInt();
  final savedMediaInterval = savedMediaIntervalMs == null
      ? mediaLibraryRequestIntervalDefault
      : Duration(milliseconds: savedMediaIntervalMs);
  ref.read(mediaLibraryRequestIntervalProvider.notifier).state =
      mediaLibraryRequestIntervalOptions.contains(savedMediaInterval)
          ? savedMediaInterval
          : mediaLibraryRequestIntervalDefault;

  // 下载线程数：只接受 UI 提供的可选值，非法配置回退默认 4
  final savedThreads = (config['downloadThreads'] as num?)?.toInt() ?? 4;
  ref.read(downloadThreadsProvider.notifier).state =
      downloadThreadOptions.contains(savedThreads) ? savedThreads : 4;

  // 并行文件数：只接受 UI 提供的可选值，非法配置回退默认 2
  final savedParallel = (config['parallelDownloadCount'] as num?)?.toInt() ?? 2;
  ref.read(parallelDownloadCountProvider.notifier).state =
      parallelDownloadOptions.contains(savedParallel) ? savedParallel : 2;

  // Debug 模式：默认 debug 构建关闭、release 构建开启（保持历史文件日志行为）
  final savedDebugMode = config['debugMode'] as bool? ?? !kDebugMode;
  ref.read(debugModeProvider.notifier).state = savedDebugMode;
  Log.setFileOutputEnabled(savedDebugMode);

  ref.read(autoOrganizeProvider.notifier).state =
      config['autoOrganize'] as bool? ?? false;
  ref.read(onlyOrganizeUnorganizedProvider.notifier).state =
      config['onlyOrganizeUnorganized'] as bool? ?? true;
  ref.read(keepOrganizeDirStructureProvider.notifier).state =
      config['keepOrganizeDirStructure'] as bool? ?? false;
  ref.read(chickenRiceScriptPathProvider.notifier).state =
      config['chickenRiceExePath'] as String? ?? '';
  ref.read(chickenRiceDeviceProvider.notifier).state =
      config['chickenRiceDevice'] as String? ?? 'auto';
  ref.read(chickenRiceTaskProvider.notifier).state =
      config['chickenRiceTask'] as String? ?? 'translate';
  ref.read(chickenRiceEngineInstallDirProvider.notifier).state =
      config['chickenRiceEngineInstallDir'] as String? ?? '';
  ref.read(chickenRiceEngineVariantProvider.notifier).state =
      config['chickenRiceEngineVariant'] as String? ?? '';
  ref.read(autoTranscribeProvider.notifier).state =
      config['autoTranscribe'] as bool? ?? false;
  ref.read(autoCheckUpdateProvider.notifier).state =
      config['autoCheckUpdate'] as bool? ?? true;
  ref.read(githubTokenProvider.notifier).state =
      config['githubToken'] as String? ?? '';
  ref.read(dismissedUpdateVersionProvider.notifier).state =
      config['dismissedUpdateVersion'] as String?;

  // 内置引擎自动检测：脚本路径配置缺失/失效但安装目录内引擎完整时，
  // 自动重新关联，避免用户已安装过引擎还要重新手动选择
  await ref.read(uiServiceProvider).autoLinkInstalledEngine();

  // 新手引导：首次启动（未完成）时延迟弹窗，早于更新检查，避免两弹窗冲突；
  // 完成或跳过后写 onboardingCompleted，之后启动不再自动弹出
  final onboardingDone = config['onboardingCompleted'] as bool? ?? false;
  ref.read(onboardingCompletedProvider.notifier).state = onboardingDone;
  if (!onboardingDone) {
    unawaited(Future.delayed(const Duration(milliseconds: 600), () async {
      final nav = navigatorKey.currentState;
      if (nav != null && nav.mounted) {
        startOnboarding(ProviderScope.containerOf(nav.context));
      }
    }));
  }

  // 自动检查更新：延迟几秒后台执行，不阻塞启动流程；
  // 发现新版本时弹更新对话框（同引擎引导弹窗模式）
  if (ref.read(autoCheckUpdateProvider)) {
    // 启动长时运行中的周期复查定时器（每 6 小时一次），
    // 与下面的启动检查配合：启动查一次 + 运行中定时复查
    ref.read(latestUpdateProvider.notifier).startPeriodicCheck();
    unawaited(Future.delayed(const Duration(seconds: 3), () async {
      try {
        final hasNew =
            await ref.read(latestUpdateProvider.notifier).check(silent: true);
        if (!hasNew) return;
        final nav = navigatorKey.currentState;
        if (nav != null && nav.mounted) {
          await showUpdateDialog(nav.context);
        }
      } catch (e) {
        Log.warning('auto check update failed\nerror: $e');
      }
    }));
  }
});
