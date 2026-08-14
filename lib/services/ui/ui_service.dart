import 'dart:io';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/api_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/tracks_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/work_info_providers.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:asmr_downloader/services/organize/navidrome_organizer.dart';
import 'package:asmr_downloader/services/transcribe/subtitle_gap_detector.dart';
import 'package:asmr_downloader/services/transcribe/transcribe_providers.dart';
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

class UIService {
  final Ref ref;
  UIService(this.ref);

  Future<void> resetProgress() async {
    ref
      ..read(processProvider.notifier).state = 0
      ..read(currentDlNoProvider.notifier).state = 0
      ..read(totalTaskCntProvider.notifier).state = 0
      ..read(currentFileNameProvider.notifier).state = ''
      ..read(downloadSpeedProvider.notifier).state = 0
      ..read(downloadEtaProvider.notifier).state = Duration.zero;
    if (Platform.isWindows) {
      await WindowsTaskbar.setProgress(0, 0);
    }
  }

  String normalizeInput(String sourceId) {
    return sourceId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
  }

  Future<String?> search(String input) async {
    await resetProgress();

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
      showSnack('无效的 sourceId，请输入 RJ/VJ/BJ 开头加数字，或粘贴 asmr.one 作品页 URL');
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

  Future<String?> pasteAndSearch() async {
    final clipBoardText = (await Clipboard.getData('text/plain'))?.text;
    if (clipBoardText == null) return null;

    // 注意：不再把旧 sourceId 写回剪贴板，避免覆盖用户剪贴板中的其他内容
    return search(clipBoardText);
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

  void onDlCoverChanged(bool? value) {
    if (value == null) return;

    ref
      ..read(dlCoverProvider.notifier).state = value
      ..read(configFileProvider).addOrUpdate({'dlCover': value});
    Log.info('dlCover: $value');
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

  /// 设置 infer.exe 路径（手动输入/选择）
  void setChickenRiceExePath(String path) {
    ref
      ..read(chickenRiceExePathProvider.notifier).state = path
      ..read(configFileProvider).addOrUpdate({'chickenRiceExePath': path});
    Log.info('chickenRiceExePath: $path');
  }

  /// 通过文件选择器选取 infer.exe
  Future<void> pickChickenRiceExe() async {
    final result =
        await FilePicker.platform.pickFiles(type: FileType.any);
    final files = result?.files;
    if (files == null || files.isEmpty) return;
    final path = files.first.path;
    if (path == null) return;
    setChickenRiceExePath(path);
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

  /// 对当前作品执行 ChickenRice 字幕翻译。
  /// 返回 true 表示已启动/完成；false 表示未执行（无作品/正在运行/无字幕缺口）。
  /// [pickExeIfEmpty] 为 true 且未配置 exe 时弹出文件选择器引导选择。
  Future<bool> transcribeCurrentWork({bool pickExeIfEmpty = false}) async {
    if (!ref.read(chickenRiceConfigProvider).isConfigured) {
      if (!pickExeIfEmpty) {
        showSnack('未配置 ChickenRice 可执行文件');
        return false;
      }
      await pickChickenRiceExe();
      if (!ref.read(chickenRiceConfigProvider).isConfigured) return false;
    }
    final probe = ref.read(chickenRiceServiceProvider).probeExe();
    if (probe != null) {
      showSnack('ChickenRice 不可用：$probe');
      return false;
    }
    if (ref.read(transcribeStatusProvider) == TranscribeStatus.running) {
      showSnack('字幕翻译正在进行中');
      return false;
    }

    final sourceId = ref.read(sourceIdProvider);
    if (sourceId == null) {
      showSnack('请先搜索作品');
      return false;
    }
    final sourceDir = p.join(ref.read(voiceWorkPathProvider), sourceId);
    if (!Directory(sourceDir).existsSync()) {
      showSnack('作品目录不存在，请先下载');
      return false;
    }

    // 预判：统计缺字幕的音轨数，给用户反馈
    final missing =
        SubtitleGapDetector.findMissingSubtitleTracks(sourceDir);
    if (missing.isEmpty) {
      showSnack('所有音轨已有字幕，无需 AI 翻译');
      return true;
    }
    Log.info('transcribe: $sourceId missing ${missing.length} subtitle tracks');

    ref
      ..read(transcribeStatusProvider.notifier).state = TranscribeStatus.running
      ..read(transcribeProgressProvider.notifier).state = null
      ..read(transcribeCancelRequestedProvider.notifier).state = false;

    final completed = await ref.read(chickenRiceServiceProvider).runOnDir(
      sourceDir,
      onProgress: (progress) {
        ref.read(transcribeProgressProvider.notifier).state = progress;
      },
      isCancelled: () =>
          ref.read(transcribeCancelRequestedProvider),
    );

    ref.read(transcribeStatusProvider.notifier).state =
        completed ? TranscribeStatus.done : TranscribeStatus.failed;
    ref.read(transcribeCancelRequestedProvider.notifier).state = false;
    showSnack(completed ? '字幕翻译完成' : '字幕翻译失败或已取消');
    return true;
  }

  /// 供「下载完成自动翻译」调用的非 UI 版本（无上下文提示直接执行）。
  /// 与 transcribeCurrentWork 共用，仅在未配置时静默跳过。
  Future<bool> autoTranscribe(String sourceId) async {
    final cfg = ref.read(chickenRiceConfigProvider);
    if (!cfg.isConfigured) return false;
    final probe = ref.read(chickenRiceServiceProvider).probeExe();
    if (probe != null) {
      Log.warning('chickenRice autoTranscribe skipped: $probe');
      return false;
    }

    // 自动触发时需要 sourceDir，但当前可能已没有搜索上下文。
    // 从 voiceWorkPath 计算：
    final sourceDir = p.join(ref.read(voiceWorkPathProvider), sourceId);
    if (!Directory(sourceDir).existsSync()) return false;

    ref
      ..read(transcribeStatusProvider.notifier).state = TranscribeStatus.running
      ..read(transcribeProgressProvider.notifier).state = null
      ..read(transcribeCancelRequestedProvider.notifier).state = false;

    final completed = await ref.read(chickenRiceServiceProvider).runOnDir(
      sourceDir,
      onProgress: (progress) {
        ref.read(transcribeProgressProvider.notifier).state = progress;
      },
      isCancelled: () =>
          ref.read(transcribeCancelRequestedProvider),
    );
    ref.read(transcribeStatusProvider.notifier).state =
        completed ? TranscribeStatus.done : TranscribeStatus.failed;
    ref.read(transcribeCancelRequestedProvider.notifier).state = false;
    return completed;
  }

  Future<void> pickDlPath() async {
    final dlPath = await FilePicker.platform.getDirectoryPath();
    if (dlPath == null) return;

    ref
      ..read(downloadPathProvider.notifier).state = dlPath
      ..read(configFileProvider).addOrUpdate({'dlPath': dlPath});
    Log.info('dlPath: $dlPath');
  }

  Future<void> pickNavidromePath() async {
    final navidromePath = await FilePicker.platform.getDirectoryPath();
    if (navidromePath == null) return;

    ref
      ..read(navidromePathProvider.notifier).state = navidromePath
      ..read(configFileProvider).addOrUpdate({'navidromePath': navidromePath});
    Log.info('navidromePath: $navidromePath');
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
    final result = await ref.read(organizeServiceProvider).organizeWork(
      sourceId: sourceId,
      sourceDir: sourceDir,
      targetRoot: navidromePath,
      workInfo: workInfo,
      fallbackTitle: ref.read(titleProvider),
      fallbackCvNames: cvNames,
      fallbackCircle: ref.read(circleNameProvider),
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
        circleName: ref.read(circleNameProvider),
        releaseDate: ref.read(releaseDateProvider),
        tags: ref.read(tagLsProvider),
        coverUrl: ref.read(coverUrlProvider),
        organizedAt: DateTime.now().toIso8601String(),
      ));
    }

    return result;
  }

  /// 手动整理当前作品到 Navidrome 媒体库结构
  Future<void> organizeToNavidrome(BuildContext context) async {
    final result = await organizeCurrentWork(pickPathIfEmpty: true);

    if (!context.mounted) return;
    if (result == null) {
      showSnack('整理失败：请先搜索并下载作品', context: context);
      return;
    }
    showSnack(context: context,
        '整理完成：复制 ${result.copied} 个文件，跳过 ${result.skipped} 个');
  }

  /// 下载完成后的自动整理（路径未设置时弹目录选择器）
  Future<void> autoOrganize() async {
    final result = await organizeCurrentWork(pickPathIfEmpty: true);

    if (result == null) {
      showSnack('自动整理未执行：未设置整理路径或作品未下载');
      return;
    }
    showSnack(
        '自动整理完成：复制 ${result.copied} 个文件，跳过 ${result.skipped} 个');
  }

  /// 弹出用户可见的提示（无 BuildContext 时走全局 scaffoldMessengerKey）。
  /// 纯逻辑调用（下载流程/单元测试）可能没有可用的 messenger，静默跳过。
  void showSnack(String message, {BuildContext? context}) {
    ScaffoldMessengerState? messenger;
    if (context != null) {
      messenger = ScaffoldMessenger.of(context);
    } else {
      try {
        messenger = scaffoldMessengerKey.currentState;
      } catch (_) {
        // WidgetsBinding 未初始化（如单元测试环境），跳过
        return;
      }
    }
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void openFolder() async {
    final vkSourceIdPath =
        p.join(ref.read(voiceWorkPathProvider), ref.read(sourceIdProvider));

    final path = Directory(vkSourceIdPath).existsSync()
        ? vkSourceIdPath
        : ref.read(downloadPathProvider);

    if (Platform.isWindows) {
      Process.run('explorer "$path"', []);
    } else {
      Process.run('open', [path]);
    }
    Log.info('open folder: "$path"');
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
