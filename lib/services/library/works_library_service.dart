import 'dart:io';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/organize_service.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:asmr_downloader/services/organize/works_scanner.dart';
import 'package:asmr_downloader/services/transcribe/subtitle_gap_detector.dart';
import 'package:asmr_downloader/services/transcribe/vtt_converter.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

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

  /// 显式作品目录路径（扁平外部导入目录），空串 = 按标准结构重建。
  final String sourceDirOverride;

  /// 最近整理时间（null = 未整理）
  final String? organizedAt;

  /// 最近一次校验结果摘要（null = 无缺陷/从未校验）
  final String? verifyNote;

  /// 缺陷是否可通过重新整理修复
  final bool verifyRepairable;

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
    required this.sourceDirOverride,
    required this.organizedAt,
    required this.verifyNote,
    required this.verifyRepairable,
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

  /// 删除本机临时下载目录，但保留作品注册表和 NAS 整理内容。
  ///
  /// 只允许删除下载根目录下的作品目录，并解析符号链接后再次校验，
  /// 防止误删下载根目录、整理目录或下载根目录之外的路径。
  Future<void> deleteLocalWork(WorksListItem item) async {
    final downloadRootPath = ref.read(downloadPathProvider).trim();
    if (downloadRootPath.isEmpty) {
      throw StateError('未设置下载路径');
    }

    final sourceDir = Directory(item.sourceDir);
    if (!await sourceDir.exists()) return;

    final downloadRoot = Directory(downloadRootPath);
    if (!await downloadRoot.exists()) {
      throw StateError('下载路径不存在');
    }

    final resolvedRoot = p.normalize(await downloadRoot.resolveSymbolicLinks());
    final resolvedSource = p.normalize(await sourceDir.resolveSymbolicLinks());
    if (p.equals(resolvedRoot, resolvedSource) ||
        !p.isWithin(resolvedRoot, resolvedSource)) {
      throw StateError('拒绝删除下载根目录之外的路径');
    }

    // 整理根目录可能位于下载根目录内；即使作品库扫描已排除它，
    // 删除前仍再次阻断，确保「删除本机下载」不会触及 NAS 目录。
    final targetRootPath = ref.read(navidromePathProvider).trim();
    if (targetRootPath.isNotEmpty) {
      final targetRoot = Directory(targetRootPath);
      if (await targetRoot.exists()) {
        final resolvedTarget =
            p.normalize(await targetRoot.resolveSymbolicLinks());
        if (p.equals(resolvedTarget, resolvedSource) ||
            p.isWithin(resolvedTarget, resolvedSource) ||
            p.isWithin(resolvedSource, resolvedTarget)) {
          throw StateError('作品目录位于整理目标中，未执行删除');
        }
      }
    }

    await sourceDir.delete(recursive: true);
  }

  /// 列出全部已下载作品（目录存在才列出）。
  ///
  /// 数据源：扫描下载根目录识别的 RJ/VJ/BJ 目录 + 注册表条目
  /// （注册表中目录仍存在但扫描遗漏的也补入），按 sourceId 倒序。
  ///
  /// 合并时注册表路径优先；仅当注册表路径已失效而扫描器发现同一
  /// sourceId 的真实目录时，用扫描到的目录字段接管并自动修复注册表，
  /// 其余元数据（标题/CV/社团/手动编辑标记等）保留注册表值。
  Future<List<WorksListItem>> listWorks() async {
    final dlRoot = ref.read(downloadPathProvider);
    final navRoot = ref.read(navidromePathProvider);
    final discovered =
        await scanDownloadRoot(dlRoot: dlRoot, excludeRoot: navRoot);

    // 下载根目录不可访问（NAS 未挂载/网络盘断开/外部磁盘未连接）时，
    // 本次扫描结果不可信：不执行任何注册表路径写回，避免临时环境问题
    // 导致错误自愈。
    final downloadRootAvailable = await Directory(dlRoot).exists();

    final registry = await ref.read(worksIndexProvider).list();
    final byId = {for (final e in registry) e.sourceId: e};

    final items = <WorksListItem>[];
    final seen = <String>{};
    for (final d in discovered) {
      final src = await _resolveSource(
        discovered: d,
        registry: byId[d.sourceId],
        downloadRootAvailable: downloadRootAvailable,
      );
      items.add(await _build(src, targetRoot: navRoot));
      seen.add(d.sourceId);
    }
    for (final r in registry) {
      if (seen.contains(r.sourceId)) continue;
      if (!Directory(r.sourceDir).existsSync()) continue;
      items.add(await _build(r, targetRoot: navRoot));
      seen.add(r.sourceId);
    }
    items.sort((a, b) => b.sourceId.compareTo(a.sourceId));
    return items;
  }

  /// 合并扫描结果与注册表条目为最终用于展示的条目。
  ///
  /// - 无注册表条目 → 直接用扫描结果；
  /// - 注册表路径仍然存在 → 保持注册表优先（即使扫描器发现另一同
  ///   sourceId 路径也不替换）；
  /// - 注册表路径已失效且扫描到的目录真实存在 → 仅用扫描结果的目录字段
  ///   （[WorkEntry.dlPath]/[WorkEntry.dirName]/[WorkEntry.sourceDirOverride]）
  ///   接管，其余元数据保留注册表值，并写回修复注册表；
  /// - 两条路径都失效 → 保持注册表原值，不做任何写入。
  Future<WorkEntry> _resolveSource({
    required WorkEntry discovered,
    required WorkEntry? registry,
    required bool downloadRootAvailable,
  }) async {
    if (registry == null || !downloadRootAvailable) {
      return registry ?? discovered;
    }
    if (await Directory(registry.sourceDir).exists()) return registry;

    // 注册表路径已失效；不能只因为存在扫描结果就修改注册表，
    // 必须确认扫描到的目录真实存在。
    if (!await Directory(discovered.sourceDir).exists()) return registry;

    final repaired = registry.copyWith(
      dlPath: discovered.dlPath,
      dirName: discovered.dirName,
      sourceDirOverride: discovered.sourceDirOverride,
    );
    Log.info(
      'WorksLibraryService: repair stale path for ${registry.sourceId}\n'
      'old: ${registry.sourceDir}\n'
      'new: ${discovered.sourceDir}',
    );
    await ref.read(worksIndexProvider).upsert(repaired);
    return repaired;
  }

  Future<WorksListItem> _build(
    WorkEntry src, {
    required String targetRoot,
  }) async {
    final parsed = OrganizeService.parseDirName(src.dirName);
    final title = src.title.isNotEmpty
        ? src.title
        : (parsed.title.isNotEmpty ? parsed.title : src.sourceId);
    final cvNames = src.cvNames.isNotEmpty ? src.cvNames : parsed.cvNames;
    final sourceDir = src.sourceDir;
    final organized = await ref.read(organizeServiceProvider).isOrganized(
          src,
          targetRoot: targetRoot,
          keepDirStructure: ref.read(keepOrganizeDirStructureProvider),
        );

    return WorksListItem(
      sourceId: src.sourceId,
      title: title,
      cvNames: cvNames,
      circleName: src.circleName,
      dirName: src.dirName,
      dlPath: src.dlPath,
      sourceDir: sourceDir,
      sourceDirOverride: src.sourceDirOverride,
      // 仅把当前文件系统仍然完整的历史整理记录暴露给列表状态。
      organizedAt: organized ? src.organizedAt : null,
      // 透传缺陷状态（never 修复入口据此判断）；verifiedAt 暂不暴露到 UI。
      verifyNote: src.verifyNote,
      verifyRepairable: src.verifyRepairable ?? false,
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
