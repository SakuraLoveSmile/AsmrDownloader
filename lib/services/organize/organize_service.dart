import 'dart:io';
import 'dart:typed_data';

import 'package:asmr_downloader/services/asmr_repo/providers/api_providers.dart';
import 'package:asmr_downloader/services/organize/navidrome_organizer.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:asmr_downloader/utils/log.dart';
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

  /// 从注册表条目整理（离线优先：直接使用注册表元数据，不现场调 API；
  /// 封面只用本地下载时保存的 {sourceId}_cover.jpg）。
  Future<OrganizeResult?> organizeEntry(WorkEntry entry,
      {required String targetRoot}) async {
    Uint8List? coverBytes;
    final localCover = File(p.join(entry.sourceDir, '${entry.sourceId}_cover.jpg'));
    if (await localCover.exists()) {
      try {
        coverBytes = await localCover.readAsBytes();
      } catch (e) {
        Log.warning('read local cover failed: ${localCover.path}\n' 'error: $e');
      }
    }

    return organizeWork(
      sourceId: entry.sourceId,
      sourceDir: entry.sourceDir,
      targetRoot: targetRoot,
      workInfo: null,
      fallbackTitle: entry.title,
      fallbackCvNames: entry.cvNames,
      fallbackCircle: entry.circleName,
      coverBytes: coverBytes,
    );
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
    entries.sort((a, b) => a.sourceId.compareTo(b.sourceId));
    if (onlyUnorganized) {
      entries = entries.where((e) => e.organizedAt == null).toList();
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
        final result = await organizeEntry(entry, targetRoot: targetRoot);
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
          await index.markOrganized(entry.sourceId);
        } else {
          success++;
          results.add(BatchItemResult(
              sourceId: entry.sourceId,
              success: true,
              message: '复制 ${result.copied} 跳过 ${result.skipped}'));
          await index.markOrganized(entry.sourceId);
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
