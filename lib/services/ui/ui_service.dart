import 'dart:io';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/api_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/tracks_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/work_info_providers.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/organize/navidrome_organizer.dart';
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

class UIService {
  final Ref ref;
  UIService(this.ref);

  Future<void> resetProgress() async {
    ref
      ..read(processProvider.notifier).state = 0
      ..read(currentDlNoProvider.notifier).state = 0
      ..read(totalTaskCntProvider.notifier).state = 0
      ..read(currentFileNameProvider.notifier).state = '';
    if (Platform.isWindows) {
      await WindowsTaskbar.setProgress(0, 0);
    }
  }

  String normalizeInput(String sourceId) {
    return sourceId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
  }

  Future<String?> search(String input) async {
    await resetProgress();

    final searchText = normalizeInput(input);
    if (!isSourceIdValid(searchText)) return null;

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

    // set old sourceId to clipboard
    final oldSourceId = ref.read(sourceIdProvider);
    if (oldSourceId != null) {
      await Clipboard.setData(ClipboardData(text: oldSourceId));
    }

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

    // 汉化版作品的 circle 是汉化组名，跟踪到原版取真实社团名
    final workInfo = ref.read(workInfoProvider).value;
    final circleName = await NavidromeOrganizer.resolveCircleName(
      workInfo: workInfo,
      fallbackCircle: ref.read(circleNameProvider),
      fetchWorkInfo: (id) => ref.read(asmrApiProvider).getWorkInfo(id),
    );

    return NavidromeOrganizer.organize(
      sourceDir: sourceDir,
      targetRoot: navidromePath,
      circleName: circleName,
      sourceId: sourceId,
      cvNames: ref.read(cvLsProvider).join('&'),
      title: ref.read(titleProvider),
      coverBytes: coverBytes,
    );
  }

  /// 手动整理当前作品到 Navidrome 媒体库结构
  Future<void> organizeToNavidrome(BuildContext context) async {
    final result = await organizeCurrentWork(pickPathIfEmpty: true);

    if (!context.mounted) return;
    if (result == null) {
      _showSnack(context, '整理失败：请先搜索并下载作品');
      return;
    }
    _showSnack(context,
        '整理完成：复制 ${result.copied} 个文件，跳过 ${result.skipped} 个');
  }

  void _showSnack(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
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
