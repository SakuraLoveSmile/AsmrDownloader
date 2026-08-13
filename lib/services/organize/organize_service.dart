import 'dart:io';
import 'dart:typed_data';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/api_providers.dart';
import 'package:asmr_downloader/services/organize/navidrome_organizer.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// 单个作品的整理结果（批量用）
class BatchItemResult {
  final String sourceId;
  final bool success;
  final String message;

  const BatchItemResult({
    required this.sourceId,
    required this.success,
    required this.message,
  });
}

/// 批量整理进度（UI 推送用）
class BatchProgress {
  final int total;
  final int done;
  final String currentSourceId;
  final List<BatchItemResult> results;

  const BatchProgress({
    required this.total,
    required this.done,
    required this.currentSourceId,
    required this.results,
  });
}

/// 批量整理汇总结果
class BatchOrganizeResult {
  final int success;
  final int failed;
  final int skipped;
  final int missing;
  final bool cancelled;
  final List<BatchItemResult> results;

  const BatchOrganizeResult({
    required this.success,
    required this.failed,
    required this.skipped,
    required this.missing,
    required this.cancelled,
    required this.results,
  });
}

/// 单条注册表/自动识别条目的整理结果（含解析后的元数据，供入库回写）。
class OrganizeEntryOutcome {
  final OrganizeResult? result;
  final WorkEntry resolvedEntry;

  const OrganizeEntryOutcome({
    required this.result,
    required this.resolvedEntry,
  });
}

/// 整理编排层：手动整理与批量整理共用。
/// 元数据来源链：注册表（下载时落盘）→ 目录名解析 → sourceId 保底；
/// 不依赖「当前搜索状态」，与下载功能解耦。
class OrganizeService {
  final Ref ref;
  OrganizeService(this.ref);

  // ---------- workInfo 字段解析（缺失走降级） ----------

  static String resolveTitle(Map<String, dynamic>? workInfo, String fallback) {
    final t = workInfo?['title']?.toString() ?? '';
    return t.isNotEmpty ? t : fallback;
  }

  static String resolveCvNames(Map<String, dynamic>? workInfo, String fallback) {
    final vas = workInfo?['vas'];
    if (vas is List && vas.isNotEmpty) {
      return vas.map((e) => e['name'].toString()).join('&');
    }
    return fallback;
  }

  static String resolveCircle(Map<String, dynamic>? workInfo, String fallback) {
    final c = workInfo?['circle']?['name']?.toString() ?? '';
    return c.isNotEmpty ? c : fallback;
  }

  static String resolveRelease(Map<String, dynamic>? workInfo) {
    return workInfo?['release']?.toString() ?? '';
  }

  static List<String> resolveTags(Map<String, dynamic>? workInfo) {
    final tags = workInfo?['tags'];
    if (tags is List) {
      return tags
          .map((e) => e['i18n']?['zh-cn']?['name']?.toString() ?? '')
          .where((t) => t.isNotEmpty)
          .toList();
    }
    return const [];
  }

  /// 从目录名解析降级元数据：目录名形如 "cv1&cv2-title"
  static ({String cvNames, String title}) parseDirName(String dirName) {
    final idx = dirName.indexOf('-');
    if (idx < 0) return (cvNames: '', title: dirName);
    return (
      cvNames: dirName.substring(0, idx).trim(),
      title: dirName.substring(idx + 1).trim(),
    );
  }

  // ---------- 核心编排 ----------

  /// 执行单个作品整理（含汉化 circle 跟踪与 artist 保底）。
  /// [workInfo] 原始 work info（可为 null，此时全部字段走降级值）；
  /// [fallbackTitle]/[fallbackCvNames]/[fallbackCircle] 为降级值
  /// （注册表缓存 / 目录名解析 / sourceId）。
  Future<OrganizeResult?> organizeWork({
    required String sourceId,
    required String sourceDir,
    required String targetRoot,
    Map<String, dynamic>? workInfo,
    required String fallbackTitle,
    required String fallbackCvNames,
    String fallbackCircle = '',
    Uint8List? coverBytes,
  }) async {
    if (!Directory(sourceDir).existsSync()) return null;

    final title = resolveTitle(workInfo, fallbackTitle);
    final cvNames = resolveCvNames(workInfo, fallbackCvNames);
    // 汉化版作品的 circle 是汉化组名，跟踪到原版取真实社团名
    final circleName = await NavidromeOrganizer.resolveCircleName(
      workInfo: workInfo,
      fallbackCircle: resolveCircle(workInfo, fallbackCircle),
      fetchWorkInfo: (id) => ref.read(asmrApiProvider).getWorkInfo(id),
    );
    // artist 保底：社团 → CV → sourceId
    final artist =
        [circleName, cvNames, sourceId].firstWhere((s) => s.isNotEmpty);

    return NavidromeOrganizer.organize(
      sourceDir: sourceDir,
      targetRoot: targetRoot,
      circleName: artist,
      sourceId: sourceId,
      cvNames: cvNames,
      title: title,
      coverBytes: coverBytes,
      artist: artist,
      albumArtist: cvNames,
      releaseDate: resolveRelease(workInfo),
      genres: resolveTags(workInfo),
    );
  }

  /// 从注册表条目整理（注册表条目离线优先：直接使用注册表元数据，不现场调 API；
  /// [fetchWorkInfo] 为 true 时（批量整理自动识别出的作品）在线拉取元数据，
  /// 失败则降级到目录名解析；封面优先本地 {sourceId}_cover.jpg，发现的作品无本地
  /// 封面时从 workInfo.mainCoverUrl 在线拉取（失败非致命）。
  Future<OrganizeEntryOutcome> organizeEntry(WorkEntry entry,
      {required String targetRoot, bool fetchWorkInfo = false}) async {
    Map<String, dynamic>? workInfo;
    if (fetchWorkInfo) {
      final digits = entry.sourceId.replaceAll(RegExp(r'[^0-9]'), '');
      try {
        workInfo = await ref.read(asmrApiProvider).getWorkInfo(digits);
      } catch (e) {
        Log.warning('fetch workInfo failed: ${entry.sourceId}\n' 'error: $e');
      }
    }

    // 降级：自动识别出的作品元数据为空时按目录名解析（"cv&cv-标题"）
    final parsed = parseDirName(entry.dirName);
    final fallbackTitle = entry.title.isNotEmpty ? entry.title : parsed.title;
    final fallbackCvNames =
        entry.cvNames.isNotEmpty ? entry.cvNames : parsed.cvNames;

    Uint8List? coverBytes;
    final localCover =
        File(p.join(entry.sourceDir, '${entry.sourceId}_cover.jpg'));
    if (await localCover.exists()) {
      try {
        coverBytes = await localCover.readAsBytes();
      } catch (e) {
        Log.warning('read local cover failed: ${localCover.path}\n' 'error: $e');
      }
    }
    // 自动识别的作品通常没有本地封面，从 workInfo 在线拉取
    if (coverBytes == null && workInfo != null) {
      final coverUrl = workInfo['mainCoverUrl']?.toString() ?? '';
      if (coverUrl.isNotEmpty) {
        try {
          coverBytes = await ref.read(asmrApiProvider).getCoverBytes(coverUrl);
        } catch (e) {
          Log.warning('fetch cover failed: ${entry.sourceId}\n' 'error: $e');
        }
      }
    }

    final result = await organizeWork(
      sourceId: entry.sourceId,
      sourceDir: entry.sourceDir,
      targetRoot: targetRoot,
      workInfo: workInfo,
      fallbackTitle: fallbackTitle,
      fallbackCvNames: fallbackCvNames,
      fallbackCircle: entry.circleName,
      coverBytes: coverBytes,
    );

    // 解析后的元数据回写（在线拉取成功时入库带真实字段；workInfo 为空保留原字段）
    final resolved = WorkEntry(
      sourceId: entry.sourceId,
      dlPath: entry.dlPath,
      dirName: entry.dirName,
      title:
          workInfo != null ? resolveTitle(workInfo, fallbackTitle) : fallbackTitle,
      cvNames: workInfo != null
          ? resolveCvNames(workInfo, fallbackCvNames)
          : fallbackCvNames,
      circleName:
          workInfo != null ? resolveCircle(workInfo, entry.circleName) : entry.circleName,
      releaseDate: workInfo != null ? resolveRelease(workInfo) : entry.releaseDate,
      tags: workInfo != null ? resolveTags(workInfo) : entry.tags,
      coverUrl: workInfo != null
          ? (workInfo['mainCoverUrl']?.toString() ?? entry.coverUrl)
          : entry.coverUrl,
      organizedAt: entry.organizedAt,
    );
    return OrganizeEntryOutcome(result: result, resolvedEntry: resolved);
  }

  // ---------- 自动识别（批量整理） ----------

  /// 扫描下载根目录，识别带 RJ/VJ/BJ 号的子目录（不依赖注册表）。
  /// 返回合成 WorkEntry（title/cvNames/circleName 为空，整理时按目录名降级解析/在线拉取）。
  /// [excludeRoot] 整理目标根目录，位于其下的目录不作为源扫描（防止把整理产物再整理）。
  /// 同一 sourceId 多处出现时取最浅路径；跳过隐藏目录。
  Future<List<WorkEntry>> discoverWorks({
    required String dlRoot,
    String? excludeRoot,
    int maxDepth = 4,
  }) async {
    if (dlRoot.isEmpty) return const [];

    final found = <String,
        ({String sourceId, String dlPath, String dirName, int depth})>{};

    Future<void> walk(Directory dir, int depth) async {
      if (depth > maxDepth) return;
      try {
        await for (final entity in dir.list()) {
          if (entity is! Directory) continue;
          final name = p.basename(entity.path);
          if (name.startsWith('.')) continue;
          if (excludeRoot != null && p.equals(entity.path, excludeRoot)) {
            continue;
          }
          final sourceId = matchSourceIdFromDirName(name);
          if (sourceId != null) {
            final prev = found[sourceId];
            if (prev == null || depth < prev.depth) {
              // 目录结构 <dlRoot>/<dirName>/<sourceId>（dirName 可为空）
              final parentPath = p.dirname(entity.path);
              final isFlat = p.equals(parentPath, dlRoot);
              found[sourceId] = (
                sourceId: sourceId,
                dlPath: isFlat ? dlRoot : p.dirname(parentPath),
                // RJ 目录直接平铺在下载根下时 dirName 为空（p.join 自动跳过空段）
                dirName: isFlat ? '' : p.basename(parentPath),
                depth: depth,
              );
            }
          }
          await walk(entity, depth + 1);
        }
      } catch (e) {
        Log.warning('scan download dir failed: ${dir.path}\n' 'error: $e');
      }
    }

    await walk(Directory(dlRoot), 1);
    return found.values
        .map((f) => WorkEntry(
              sourceId: f.sourceId,
              dlPath: f.dlPath,
              dirName: f.dirName,
              title: '',
              cvNames: '',
            ))
        .toList();
  }

  // ---------- 批量整理 ----------

  /// 批量整理注册表中所有（或仅未整理的）作品。
  /// [onProgress] 每处理完一个作品回调一次进度；
  /// [isCancelled] 返回 true 时在当前作品完成后停止。
  Future<BatchOrganizeResult> organizeAll({
    required String targetRoot,
    required bool onlyUnorganized,
    required void Function(BatchProgress) onProgress,
    required bool Function() isCancelled,
  }) async {
    final index = ref.read(worksIndexProvider);
    var entries = await index.list();
    // 全量注册表（用于自动识别去重与目录移动修正，不随 onlyUnorganized 过滤）
    final registeredAll = {for (final e in entries) e.sourceId: e};
    entries.sort((a, b) => a.sourceId.compareTo(b.sourceId));
    if (onlyUnorganized) {
      entries = entries.where((e) => e.organizedAt == null).toList();
    }

    // 自动识别下载目录中带 RJ/VJ/BJ 号的目录：
    // - 未注册的加入待整理列表（在线拉取元数据，失败降级目录名）；
    // - 注册表路径过期但发现新路径时修正注册表；
    // - 目标目录与下载目录重叠时跳过扫描（防止把整理产物再整理）。
    final discoveredIds = <String>{};
    final dlRoot = ref.read(downloadPathProvider);
    final canScan = dlRoot.isNotEmpty &&
        !p.equals(targetRoot, dlRoot) &&
        !p.isWithin(targetRoot, dlRoot);
    if (canScan) {
      final discovered =
          await discoverWorks(dlRoot: dlRoot, excludeRoot: targetRoot);
      for (final d in discovered) {
        final existing = registeredAll[d.sourceId];
        if (existing == null) {
          discoveredIds.add(d.sourceId);
          entries.add(d);
        } else if (!Directory(existing.sourceDir).existsSync() &&
            Directory(d.sourceDir).existsSync()) {
          // 目录被移动：修正注册表路径，本次按新路径整理
          final fixed = existing.copyWith(dlPath: d.dlPath, dirName: d.dirName);
          await index.upsert(fixed);
          final idx = entries.indexWhere((e) => e.sourceId == d.sourceId);
          if (idx >= 0) entries[idx] = fixed;
        }
      }
      entries.sort((a, b) => a.sourceId.compareTo(b.sourceId));
      if (discoveredIds.isNotEmpty) {
        Log.info('batch organize: discovered ${discoveredIds.length} '
            'unregistered works: ${discoveredIds.join(', ')}');
      }
    }

    final results = <BatchItemResult>[];
    var success = 0;
    var failed = 0;
    var skipped = 0;
    var missing = 0;
    var cancelled = false;

    for (var i = 0; i < entries.length; i++) {
      if (isCancelled()) {
        cancelled = true;
        break;
      }
      final entry = entries[i];
      onProgress(BatchProgress(
        total: entries.length,
        done: i,
        currentSourceId: entry.sourceId,
        results: List.of(results),
      ));

      if (!Directory(entry.sourceDir).existsSync()) {
        missing++;
        results.add(BatchItemResult(
            sourceId: entry.sourceId, success: false, message: '下载目录不存在'));
        continue;
      }

      try {
        final outcome = await organizeEntry(entry,
            targetRoot: targetRoot,
            fetchWorkInfo: discoveredIds.contains(entry.sourceId));
        final result = outcome.result;
        if (result == null) {
          failed++;
          results.add(BatchItemResult(
              sourceId: entry.sourceId, success: false, message: '整理未执行'));
        } else if (result.copied == 0) {
          skipped++;
          results.add(BatchItemResult(
              sourceId: entry.sourceId,
              success: true,
              message: '已是最新（复制 0 跳过 ${result.skipped}）'));
          await index.upsert(outcome.resolvedEntry
              .copyWith(organizedAt: DateTime.now().toIso8601String()));
        } else {
          success++;
          results.add(BatchItemResult(
              sourceId: entry.sourceId,
              success: true,
              message: '复制 ${result.copied} 跳过 ${result.skipped}'));
          await index.upsert(outcome.resolvedEntry
              .copyWith(organizedAt: DateTime.now().toIso8601String()));
        }
      } catch (e) {
        failed++;
        results.add(BatchItemResult(
            sourceId: entry.sourceId, success: false, message: '失败: $e'));
      }
    }

    onProgress(BatchProgress(
      total: entries.length,
      done: entries.length,
      currentSourceId: '',
      results: List.of(results),
    ));

    return BatchOrganizeResult(
      success: success,
      failed: failed,
      skipped: skipped,
      missing: missing,
      cancelled: cancelled,
      results: results,
    );
  }
}
