import 'dart:io';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/organize_service.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:asmr_downloader/services/organize/works_scanner.dart';
import 'package:asmr_downloader/services/transcribe/subtitle_gap_detector.dart';
import 'package:asmr_downloader/services/transcribe/vtt_converter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 作品库列表项：一个已下载作品的展示与操作数据。
class WorksListItem {
  final String sourceId;

  /// 标题（注册表 → 目录名解析 → sourceId 降级）
  final String title;

  /// CV 名单（& 连接）
  final String cvNames;

  final String circleName;

  /// 作品目录名（cv&cv-标题）
  final String dirName;

  /// 下载根目录（dlPath），与 [dirName] 拼出下载目录
  final String dlPath;

  /// 作品下载目录绝对路径
  final String sourceDir;

  /// 最近整理时间（null = 未整理）
  final String? organizedAt;

  /// 音轨总数
  final int trackCount;

  /// 缺少任何字幕（lrc/vtt/srt）的音轨数
  final int missingSubtitleCount;

  /// 可转换为 lrc 的 vtt 数
  final int convertibleVttCount;

  const WorksListItem({
    required this.sourceId,
    required this.title,
    required this.cvNames,
    required this.circleName,
    required this.dirName,
    required this.dlPath,
    required this.sourceDir,
    required this.organizedAt,
    required this.trackCount,
    required this.missingSubtitleCount,
    required this.convertibleVttCount,
  });

  bool get organized => organizedAt != null;
}

/// 作品库数据服务：扫描下载目录 + 合并注册表元数据 + 统计字幕缺口。
class WorksLibraryService {
  final Ref ref;
  WorksLibraryService(this.ref);

  /// 列出全部已下载作品（目录存在才列出）。
  ///
  /// 数据源：扫描下载根目录识别的 RJ/VJ/BJ 目录 + 注册表条目
  /// （注册表中目录仍存在但扫描遗漏的也补入），按 sourceId 倒序。
  Future<List<WorksListItem>> listWorks() async {
    final dlRoot = ref.read(downloadPathProvider);
    final navRoot = ref.read(navidromePathProvider);
    final discovered =
        await scanDownloadRoot(dlRoot: dlRoot, excludeRoot: navRoot);

    final registry = await ref.read(worksIndexProvider).list();
    final byId = {for (final e in registry) e.sourceId: e};

    final items = <WorksListItem>[];
    final seen = <String>{};
    for (final d in discovered) {
      items.add(await _build(d, byId[d.sourceId], targetRoot: navRoot));
      seen.add(d.sourceId);
    }
    for (final r in registry) {
      if (seen.contains(r.sourceId)) continue;
      if (!Directory(r.sourceDir).existsSync()) continue;
      items.add(await _build(r, r, targetRoot: navRoot));
      seen.add(r.sourceId);
    }
    items.sort((a, b) => b.sourceId.compareTo(a.sourceId));
    return items;
  }

  Future<WorksListItem> _build(
    WorkEntry discovered,
    WorkEntry? registry, {
    required String targetRoot,
  }) async {
    final src = registry ?? discovered;
    final parsed = OrganizeService.parseDirName(src.dirName);
    final title = src.title.isNotEmpty
        ? src.title
        : (parsed.title.isNotEmpty ? parsed.title : src.sourceId);
    final cvNames = src.cvNames.isNotEmpty ? src.cvNames : parsed.cvNames;
    final sourceDir = src.sourceDir;
    final organized = await ref.read(organizeServiceProvider).isOrganized(
          src,
          targetRoot: targetRoot,
        );

    return WorksListItem(
      sourceId: src.sourceId,
      title: title,
      cvNames: cvNames,
      circleName: src.circleName,
      dirName: src.dirName,
      dlPath: src.dlPath,
      sourceDir: sourceDir,
      // 仅把当前文件系统仍然完整的历史整理记录暴露给列表状态。
      organizedAt: organized ? src.organizedAt : null,
      // 用异步扫描版本：列表构建在 UI isolate 上，同步遍历大量目录会卡顿
      trackCount: await SubtitleGapDetector.countAudioFilesAsync(sourceDir),
      missingSubtitleCount:
          (await SubtitleGapDetector.findMissingSubtitleTracksAsync(sourceDir))
              .length,
      convertibleVttCount:
          (await VttConverter.findConvertibleVttsAsync(sourceDir)).length,
    );
  }
}
