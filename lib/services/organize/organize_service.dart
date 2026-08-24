import 'dart:io';
import 'dart:typed_data';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/api_providers.dart';
import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:asmr_downloader/services/organize/navidrome_organizer.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:asmr_downloader/services/organize/works_scanner.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// 单个作品的整理结果（批量用）
class BatchItemResult {
  final String sourceId;
  final bool success;
  final String message;
  /// 下载目录不存在（缺失），与「整理失败」分开统计与展示。
  final bool missing;

  const BatchItemResult({
    required this.sourceId,
    required this.success,
    required this.message,
    this.missing = false,
  });
}

/// 批量整理进度（UI 推送用）
class BatchProgress {
  final int total;
  final int done;
  final String currentSourceId;
  final String statusMessage;
  final List<BatchItemResult> results;

  const BatchProgress({
    required this.total,
    required this.done,
    required this.currentSourceId,
    this.statusMessage = '',
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
  final String? metadataNote;

  /// 整理产物校验摘要（如「校验通过」「校验：2 首缺歌词、封面 cover.jpg 缺失」），
  /// 校验未执行（取消/异常）时为 null。
  final String? verifyNote;

  const OrganizeEntryOutcome({
    required this.result,
    required this.resolvedEntry,
    this.metadataNote,
    this.verifyNote,
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

  static String resolveCvNames(
      Map<String, dynamic>? workInfo, String fallback) {
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

  /// 音频标签多值分隔符：Navidrome 按分号拆分单值 artist/albumartist 标签，
  /// "&" 会被当作名字的一部分（如 "a&b" 识别为一个 CV 而非两个）。
  static String toArtistTagValue(String cvNames) {
    return cvNames
        .split('&')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join('; ');
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

  /// 判断注册表条目当前是否仍有完整的整理产物。
  ///
  /// `organizedAt` 作为历史整理记录保留，但不能单独代表目标文件仍存在。
  Future<bool> isOrganized(
    WorkEntry entry, {
    required String targetRoot,
    bool keepDirStructure = false,
  }) async {
    if (entry.organizedAt == null) return false;
    return NavidromeOrganizer.hasExpectedFiles(
      sourceDir: entry.sourceDir,
      targetRoot: targetRoot,
      circleName: entry.circleName,
      sourceId: entry.sourceId,
      cvNames: entry.cvNames,
      title: entry.title,
      keepDirStructure: keepDirStructure,
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
    String? resolvedCircleName,
    Uint8List? coverBytes,
    bool keepDirStructure = false,
    bool forceWavRewrite = false,
  }) async {
    if (!Directory(sourceDir).existsSync()) return null;

    final title = resolveTitle(workInfo, fallbackTitle);
    final cvNames = resolveCvNames(workInfo, fallbackCvNames);
    // 汉化版作品的 circle 是汉化组名，跟踪到原版取真实社团名
    // （原版元数据缓存优先，避免重复请求 API）
    final circleName = resolvedCircleName ??
        await NavidromeOrganizer.resolveCircleName(
          workInfo: workInfo,
          fallbackCircle: resolveCircle(workInfo, fallbackCircle),
          fetchWorkInfo: fetchWorkInfoCached,
        );
    // circle 目录名（汉化跟踪后的社团名）保底：社团 → CV → sourceId
    final circleDirName =
        [circleName, cvNames, sourceId].firstWhere((s) => s.isNotEmpty);
    // 音频 artist/albumArtist 标签 = CV 声优（用户需求：艺术家是声优而非社团名）
    // 多 CV 用 "; " 分隔：Navidrome 据此拆分为多个独立艺术家
    final artistTag = toArtistTagValue(cvNames);

    return NavidromeOrganizer.organize(
      sourceDir: sourceDir,
      targetRoot: targetRoot,
      circleName: circleDirName,
      sourceId: sourceId,
      cvNames: cvNames,
      title: title,
      coverBytes: coverBytes,
      artist: artistTag,
      albumArtist: artistTag,
      releaseDate: resolveRelease(workInfo),
      genres: resolveTags(workInfo),
      keepDirStructure: keepDirStructure,
      forceWavRewrite: forceWavRewrite,
    );
  }

  /// 从注册表条目整理。
  ///
  /// 注册表可能由旧版本写入过汉化组名，因此即使 [entry.circleName] 非空，
  /// 也默认重新读取 workInfo（缓存优先），再解析原版社团名。这样单条整理、
  /// 批量整理和重新整理都不会被旧的中文社团字段短路。失败则降级到注册表/目录名。
  Future<OrganizeEntryOutcome> organizeEntry(
    WorkEntry entry, {
    required String targetRoot,
    bool fetchWorkInfo = true,
    bool keepDirStructure = false,
    bool forceWavRewrite = false,
  }) async {
    Map<String, dynamic>? workInfo;
    String? metadataNote;
    if (fetchWorkInfo || entry.circleName.trim().isEmpty) {
      try {
        // 缓存优先：命中时保持离线快速路径，未命中才请求 API。
        workInfo = await fetchWorkInfoCached(entry.sourceId);
        if (workInfo == null) {
          metadataNote = '元数据未找到，已按本地信息整理';
        } else if (resolveCircle(workInfo, '').isEmpty) {
          metadataNote = '元数据不完整（缺少社团名），已按本地信息整理';
        }
      } catch (e) {
        Log.warning('fetch workInfo failed: ${entry.sourceId}\n' 'error: $e');
        final errorText = e.toString().replaceFirst('Exception: ', '');
        metadataNote = '元数据获取失败（$errorText），已按本地信息整理';
      }
    }

    // 降级：自动识别出的作品元数据为空时按目录名解析（"cv&cv-标题"）
    final parsed = parseDirName(entry.dirName);
    final fallbackTitle = entry.title.isNotEmpty ? entry.title : parsed.title;
    final fallbackCvNames =
        entry.cvNames.isNotEmpty ? entry.cvNames : parsed.cvNames;

    // 只解析一次并把同一个结果传给整理和注册表回写；否则目录虽然已经用
    // 原版社团名创建，回写时又会把旧的汉化组名保存回去，下一次仍会复发。
    final resolvedCircleName = workInfo == null
        ? entry.circleName
        : await NavidromeOrganizer.resolveCircleName(
            workInfo: workInfo,
            fallbackCircle: resolveCircle(workInfo, entry.circleName),
            fetchWorkInfo: fetchWorkInfoCached,
          );

    Uint8List? coverBytes;
    var coverNote = '';
    final localCover =
        File(p.join(entry.sourceDir, '${entry.sourceId}_cover.jpg'));
    if (await localCover.exists()) {
      try {
        coverBytes = await localCover.readAsBytes();
      } catch (e) {
        Log.warning(
            'read local cover failed: ${localCover.path}\n' 'error: $e');
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
          coverNote = '封面获取失败，已跳过';
        }
      }
    }
    if (coverNote.isNotEmpty) {
      metadataNote = (metadataNote == null || metadataNote.isEmpty)
          ? coverNote
          : '$metadataNote；$coverNote';
    }

    final result = await organizeWork(
      sourceId: entry.sourceId,
      sourceDir: entry.sourceDir,
      targetRoot: targetRoot,
      workInfo: workInfo,
      fallbackTitle: fallbackTitle,
      fallbackCvNames: fallbackCvNames,
      fallbackCircle: entry.circleName,
      resolvedCircleName: resolvedCircleName,
      coverBytes: coverBytes,
      keepDirStructure: keepDirStructure,
      forceWavRewrite: forceWavRewrite,
    );

    // 解析后的元数据回写（在线拉取成功时入库带真实字段；workInfo 为空保留原字段）
    final resolved = WorkEntry(
      sourceId: entry.sourceId,
      dlPath: entry.dlPath,
      dirName: entry.dirName,
      title: workInfo != null
          ? resolveTitle(workInfo, fallbackTitle)
          : fallbackTitle,
      cvNames: workInfo != null
          ? resolveCvNames(workInfo, fallbackCvNames)
          : fallbackCvNames,
      circleName: resolvedCircleName,
      releaseDate:
          workInfo != null ? resolveRelease(workInfo) : entry.releaseDate,
      tags: workInfo != null ? resolveTags(workInfo) : entry.tags,
      coverUrl: workInfo != null
          ? (workInfo['mainCoverUrl']?.toString() ?? entry.coverUrl)
          : entry.coverUrl,
      organizedAt: entry.organizedAt,
    );

    // 整理产物校验（缺歌词/封面等缺陷摘要，供批量消息与 snack 展示）。
    // 校验只读不修改文件；用解析后的 resolvedEntry 保证目标目录与本次整理一致。
    String? verifyNote;
    if (result != null) {
      try {
        final verify = await ref.read(verifyServiceProvider).verifyWork(
              resolved,
              targetRoot: targetRoot,
              keepDirStructure: keepDirStructure,
            );
        verifyNote = verify.ok ? '校验通过' : '校验：${verify.summary}';
      } catch (e) {
        Log.warning('verify work failed: ${entry.sourceId}\n' 'error: $e');
      }
    }

    return OrganizeEntryOutcome(
      result: result,
      resolvedEntry: resolved,
      metadataNote: metadataNote,
      verifyNote: verifyNote,
    );
  }

  /// 缓存优先拉取 workInfo（供汉化版原版 circle 跟踪等场景复用）。
  /// [id] 可为完整 sourceId（RJ/VJ/BJ + 数字）或纯数字 id：
  /// - 完整 sourceId 直接查缓存；
  /// - 纯数字 id 先按数字段扫描已有缓存条目；
  /// - 未命中时请求 API（数字 id），成功后按响应自带的 source_id 入库。
  Future<Map<String, dynamic>?> fetchWorkInfoCached(String id) async {
    final cache = ref.read(cacheServiceProvider);
    final digits = id.replaceAll(RegExp(r'[^0-9]'), '');

    String? cacheKey;
    if (RegExp(r'^(RJ|VJ|BJ)\d+$', caseSensitive: false).hasMatch(id)) {
      cacheKey = id.toUpperCase();
      final cached = await cache.getWorkInfo(cacheKey);
      if (cached != null) {
        Log.info('resolveCircleName workInfo cache hit: $cacheKey');
        return cached;
      }
    } else if (digits.isNotEmpty) {
      cacheKey = await cache.findSourceIdByDigits(digits);
      if (cacheKey != null) {
        final cached = await cache.getWorkInfo(cacheKey);
        if (cached != null) {
          Log.info('resolveCircleName workInfo cache hit: $cacheKey');
          return cached;
        }
      }
    }

    final data = await ref.read(asmrApiProvider).getWorkInfoOrThrow(digits);
    if (data != null) {
      final respSourceId = data['source_id']?.toString().toUpperCase();
      if (respSourceId != null && respSourceId.isNotEmpty) {
        await cache.saveWorkInfo(respSourceId, data);
      } else if (cacheKey != null) {
        await cache.saveWorkInfo(cacheKey, data);
      }
    }
    return data;
  }

  /// 判断整理时是否需要访问网络获取 workInfo。
  Future<bool> _hasCachedWorkInfo(String id) async {
    final cache = ref.read(cacheServiceProvider);
    final digits = id.replaceAll(RegExp(r'[^0-9]'), '');
    String? cacheKey;
    if (RegExp(r'^(RJ|VJ|BJ)\d+$', caseSensitive: false).hasMatch(id)) {
      cacheKey = id.toUpperCase();
    } else if (digits.isNotEmpty) {
      cacheKey = await cache.findSourceIdByDigits(digits);
    }
    if (cacheKey == null) return false;
    return await cache.getWorkInfo(cacheKey) != null;
  }

  /// 判断整理条目是否会触发 workInfo 网络请求。
  Future<bool> needsWorkInfoNetwork(WorkEntry entry,
      {bool fetchWorkInfo = false}) async {
    if (!fetchWorkInfo && entry.circleName.trim().isNotEmpty) return false;
    return !await _hasCachedWorkInfo(entry.sourceId);
  }

  // ---------- 自动识别（批量整理） ----------

  /// 扫描下载根目录，识别带 RJ/VJ/BJ 号的子目录（不依赖注册表）。
  /// 返回合成 WorkEntry（title/cvNames/circleName 为空，整理时按目录名降级解析/在线拉取）。
  /// [excludeRoot] 整理目标根目录，位于其下的目录不作为源扫描（防止把整理产物再整理）。
  /// 同一 sourceId 多处出现时取最浅路径；跳过隐藏目录。
  /// 实现委托给公共 [scanDownloadRoot]（作品库列表复用同一扫描逻辑）。
  Future<List<WorkEntry>> discoverWorks({
    required String dlRoot,
    String? excludeRoot,
    int maxDepth = 4,
  }) {
    return scanDownloadRoot(
      dlRoot: dlRoot,
      excludeRoot: excludeRoot,
      maxDepth: maxDepth,
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
    bool keepDirStructure = false,
  }) async {
    final index = ref.read(worksIndexProvider);
    var entries = await index.list();
    // 全量注册表（用于自动识别去重与目录移动修正，不随 onlyUnorganized 过滤）
    final registeredAll = {for (final e in entries) e.sourceId: e};
    entries.sort((a, b) => a.sourceId.compareTo(b.sourceId));

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

    if (onlyUnorganized) {
      final unorganized = <WorkEntry>[];
      for (final entry in entries) {
        if (!await isOrganized(entry,
            targetRoot: targetRoot, keepDirStructure: keepDirStructure)) {
          unorganized.add(entry);
        }
      }
      entries = unorganized;
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
      // 即使注册表已有 circle，也要读取 workInfo：旧版本可能保存的是汉化组名，
      // 只有这样才能可靠地解析并回写原版社团名。
      final needsNetwork = Directory(entry.sourceDir).existsSync() &&
          !await _hasCachedWorkInfo(entry.sourceId);
      onProgress(BatchProgress(
        total: entries.length,
        done: i,
        currentSourceId: entry.sourceId,
        statusMessage: needsNetwork ? '获取元数据中…' : '整理文件中…',
        results: List.of(results),
      ));

      if (!Directory(entry.sourceDir).existsSync()) {
        missing++;
        results.add(BatchItemResult(
            sourceId: entry.sourceId,
            success: false,
            message: '下载目录不存在',
            missing: true));
        continue;
      }

      try {
        final outcome = await organizeEntry(entry,
            targetRoot: targetRoot,
            // 批量整理也必须刷新已有注册表条目的元数据；旧版本可能把
            // 汉化组名写进 circleName，不能只对新扫描到的作品联网。
            fetchWorkInfo: true,
            keepDirStructure: keepDirStructure);
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
              message: _appendVerifyNote(
                  _appendMetadataNote(
                      _appendTagNote('已是最新（复制 0 跳过 ${result.skipped}）',
                          result.tagWriteFailures),
                      outcome.metadataNote),
                  outcome.verifyNote)));
          await index.upsert(outcome.resolvedEntry
              .copyWith(organizedAt: DateTime.now().toIso8601String()));
        } else {
          success++;
          results.add(BatchItemResult(
              sourceId: entry.sourceId,
              success: true,
              message: _appendVerifyNote(
                  _appendMetadataNote(
                      _appendTagNote('复制 ${result.copied} 跳过 ${result.skipped}',
                          result.tagWriteFailures),
                      outcome.metadataNote),
                  outcome.verifyNote)));
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
      statusMessage: '',
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

  static String _appendMetadataNote(String message, String? metadataNote) {
    if (metadataNote == null || metadataNote.isEmpty) return message;
    return '$message；$metadataNote';
  }

  static String _appendVerifyNote(String message, String? verifyNote) {
    if (verifyNote == null || verifyNote.isEmpty) return message;
    return '$message；$verifyNote';
  }

  static String _appendTagNote(String message, int tagWriteFailures) {
    if (tagWriteFailures <= 0) return message;
    return '$message；$tagWriteFailures 个文件标签写入失败';
  }
}
