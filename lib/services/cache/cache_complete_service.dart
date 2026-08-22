import 'dart:convert';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/asmr_api.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/api_providers.dart';
import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:asmr_downloader/services/cache/cache_service.dart';
import 'package:asmr_downloader/services/library/media_library_service.dart';
import 'package:asmr_downloader/services/organize/navidrome_organizer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 补全缺失缓存时的进度。
class CompleteProgress {
  final int tracksFilled;
  final int coversFilled;
  final int failed;
  final String currentSourceId;
  final int totalTracksMissing;
  final int totalCoversMissing;

  const CompleteProgress({
    required this.tracksFilled,
    required this.coversFilled,
    required this.failed,
    required this.currentSourceId,
    required this.totalTracksMissing,
    required this.totalCoversMissing,
  });
}

/// 补全缺失缓存的汇总结果。
class CompleteResult {
  final int tracksFilled;
  final int coversFilled;
  final int failed;
  final bool cancelled;

  const CompleteResult({
    required this.tracksFilled,
    required this.coversFilled,
    required this.failed,
    required this.cancelled,
  });
}

/// 一键补全媒体库时的进度。
///
/// [total] 和 [processed] 按扫描到的作品数统计；其余字段按实际补全的
/// 缓存项统计，方便用户区分“作品进度”和“具体补了什么”。
class MediaLibraryCompleteProgress {
  const MediaLibraryCompleteProgress({
    required this.processed,
    required this.total,
    required this.metadataFilled,
    required this.originalCirclesFilled,
    required this.tracksFilled,
    required this.coversFilled,
    required this.skipped,
    required this.failed,
    required this.currentSourceId,
    required this.phase,
  });

  final int processed;
  final int total;
  final int metadataFilled;
  final int originalCirclesFilled;
  final int tracksFilled;
  final int coversFilled;
  final int skipped;
  final int failed;
  final String currentSourceId;
  final String phase;
}

/// 一键补全媒体库的汇总结果。
class MediaLibraryCompleteResult {
  const MediaLibraryCompleteResult({
    required this.processed,
    required this.total,
    required this.metadataFilled,
    required this.originalCirclesFilled,
    required this.tracksFilled,
    required this.coversFilled,
    required this.skipped,
    required this.failed,
    required this.cancelled,
  });

  final int processed;
  final int total;
  final int metadataFilled;
  final int originalCirclesFilled;
  final int tracksFilled;
  final int coversFilled;
  final int skipped;
  final int failed;
  final bool cancelled;
}

/// 为已有 workInfo 缓存的作品补全 tracks 和封面缓存。
class CacheCompleteService {
  CacheCompleteService(this.ref);

  final Ref ref;

  /// 补全请求至少使用批量缓存的默认间隔，避免连续补 tracks/封面时过于密集。
  static const Duration completeRunInterval = Duration(seconds: 2);

  /// 扫描当前媒体库并一键补全：当前作品 workInfo、日文原版 workInfo、
  /// tracks 和封面。只处理扫描根目录中发现的作品，不影响其它缓存条目。
  Future<MediaLibraryCompleteResult> completeMediaLibrary({
    Duration? runInterval,
    required void Function(MediaLibraryCompleteProgress) onProgress,
    required bool Function() isCancelled,
  }) async {
    final cache = ref.read(cacheServiceProvider);
    final api = ref.read(asmrApiProvider);
    final mediaLibrary = ref.read(mediaLibraryServiceProvider);
    final limiter = ref.read(rateLimiterProvider);
    final originalInterval = limiter.minInterval;
    if (runInterval != null) {
      limiter.minInterval = runInterval;
    } else if (originalInterval < completeRunInterval) {
      limiter.minInterval = completeRunInterval;
    }

    int metadataFilled = 0;
    int originalCirclesFilled = 0;
    int tracksFilled = 0;
    int coversFilled = 0;
    int skipped = 0;
    int failed = 0;
    int processed = 0;
    int total = 0;
    bool cancelled = false;

    try {
      await mediaLibrary.scanConfiguredRoots();
      final locations = await mediaLibrary.listLocations(
        roots: ref.read(mediaLibraryRootsProvider),
      );
      final sourceIds = locations
          .map((location) => location.sourceId)
          .toSet()
          .toList()
        ..sort();
      total = sourceIds.length;

      final workInfoEntries = await cache.listWorkInfoEntries();
      final workInfoById = <String, Map<String, dynamic>>{
        for (final entry in workInfoEntries)
          entry.sourceId: _decodeWorkInfo(entry.workInfoJson),
      };
      final tracksSourceIds = await cache.listTracksSourceIds();
      final coverSourceIds = await cache.listCoverSourceIds();

      onProgress(MediaLibraryCompleteProgress(
        processed: 0,
        total: total,
        metadataFilled: metadataFilled,
        originalCirclesFilled: originalCirclesFilled,
        tracksFilled: tracksFilled,
        coversFilled: coversFilled,
        skipped: skipped,
        failed: failed,
        currentSourceId: '',
        phase: '扫描完成',
      ));

      for (final sourceId in sourceIds) {
        if (isCancelled()) {
          cancelled = true;
          break;
        }

        var itemFailed = false;
        var attempted = false;
        var phase = '检查缓存';
        var workInfo = workInfoById[sourceId] ??
            await cache.getWorkInfo(sourceId) ??
            const <String, dynamic>{};

        if (workInfo.isEmpty) {
          attempted = true;
          phase = '补全元数据';
          try {
            final fetched = await _fetchWorkInfoForSource(
              sourceId: sourceId,
              cache: cache,
              api: api,
            );
            if (fetched == null) {
              itemFailed = true;
            } else {
              workInfo = fetched;
              workInfoById[sourceId] = fetched;
              metadataFilled++;
            }
          } catch (_) {
            itemFailed = true;
          }
        }

        final originalCandidates =
            NavidromeOrganizer.originalWorkCandidates(workInfo);
        if (originalCandidates.isNotEmpty) {
          attempted = true;
          phase = '解析原版社团';
          final hadCachedOriginal = await _hasCachedCandidate(
            cache,
            originalCandidates,
          );
          try {
            final resolved = await NavidromeOrganizer.resolveCircleNames(
              workInfo: workInfo,
              fallbackCircle: _circleName(workInfo),
              fetchWorkInfo: (id) => _fetchWorkInfoCachedOrRemote(
                id: id,
                cache: cache,
                api: api,
              ),
            );
            if (!resolved.originalResolved) {
              itemFailed = true;
            } else if (!hadCachedOriginal) {
              originalCirclesFilled++;
            }
          } catch (_) {
            itemFailed = true;
          }
        }

        final workId = _workId(workInfo, sourceId);
        if (!tracksSourceIds.contains(sourceId)) {
          attempted = true;
          phase = '补全 tracks';
          if (workId.isNotEmpty) {
            try {
              final tracks = await api.getTracks(workId);
              if (tracks == null) {
                itemFailed = true;
              } else {
                await cache.saveTracks(sourceId, tracks);
                tracksSourceIds.add(sourceId);
                tracksFilled++;
              }
            } catch (_) {
              itemFailed = true;
            }
          }
        }

        if (!coverSourceIds.contains(sourceId)) {
          attempted = true;
          phase = '补全封面';
          final coverUrl = workInfo['mainCoverUrl']?.toString() ?? '';
          if (coverUrl.isNotEmpty) {
            try {
              final bytes = await api.getCoverBytes(coverUrl);
              if (bytes == null) {
                itemFailed = true;
              } else {
                await cache.saveCover(sourceId, bytes);
                coverSourceIds.add(sourceId);
                coversFilled++;
              }
            } catch (_) {
              itemFailed = true;
            }
          }
        }

        if (itemFailed) {
          failed++;
        } else if (!attempted) {
          skipped++;
        }
        processed++;
        onProgress(MediaLibraryCompleteProgress(
          processed: processed,
          total: total,
          metadataFilled: metadataFilled,
          originalCirclesFilled: originalCirclesFilled,
          tracksFilled: tracksFilled,
          coversFilled: coversFilled,
          skipped: skipped,
          failed: failed,
          currentSourceId: sourceId,
          phase: phase,
        ));
      }
    } finally {
      limiter.minInterval = originalInterval;
    }

    return MediaLibraryCompleteResult(
      processed: processed,
      total: total,
      metadataFilled: metadataFilled,
      originalCirclesFilled: originalCirclesFilled,
      tracksFilled: tracksFilled,
      coversFilled: coversFilled,
      skipped: skipped,
      failed: failed,
      cancelled: cancelled,
    );
  }

  Future<CompleteResult> completeMissing({
    Duration? runInterval,
    required void Function(CompleteProgress) onProgress,
    required bool Function() isCancelled,
  }) async {
    final cache = ref.read(cacheServiceProvider);
    final api = ref.read(asmrApiProvider);
    final limiter = ref.read(rateLimiterProvider);
    final originalInterval = limiter.minInterval;
    if (runInterval != null) {
      limiter.minInterval = runInterval;
    } else if (originalInterval < completeRunInterval) {
      limiter.minInterval = completeRunInterval;
    }

    int tracksFilled = 0;
    int coversFilled = 0;
    int failed = 0;
    bool cancelled = false;

    try {
      final workInfoEntries = await cache.listWorkInfoEntries();
      final tracksSourceIds = await cache.listTracksSourceIds();
      final coverSourceIds = await cache.listCoverSourceIds();
      final candidates = workInfoEntries.where((entry) {
        return !tracksSourceIds.contains(entry.sourceId) ||
            !coverSourceIds.contains(entry.sourceId);
      }).toList();

      final totalTracksMissing = candidates
          .where((entry) => !tracksSourceIds.contains(entry.sourceId))
          .length;
      final totalCoversMissing = candidates
          .where((entry) => !coverSourceIds.contains(entry.sourceId))
          .length;

      // 让 UI 在没有候选项或首条请求尚未完成时也能显示总数。
      onProgress(CompleteProgress(
        tracksFilled: tracksFilled,
        coversFilled: coversFilled,
        failed: failed,
        currentSourceId: '',
        totalTracksMissing: totalTracksMissing,
        totalCoversMissing: totalCoversMissing,
      ));

      for (final entry in candidates) {
        if (isCancelled()) {
          cancelled = true;
          break;
        }

        final sourceId = entry.sourceId;
        final workInfo = _decodeWorkInfo(entry.workInfoJson);
        final id = _workId(workInfo, sourceId);
        bool itemFailed = false;

        if (!tracksSourceIds.contains(sourceId)) {
          if (id.isEmpty) {
            // 没有可推导的数字 id 时只能补封面，tracks 留待下次处理。
          } else {
            try {
              final tracks = await api.getTracks(id);
              if (tracks == null) {
                itemFailed = true;
              } else {
                await cache.saveTracks(sourceId, tracks);
                tracksFilled++;
              }
            } catch (_) {
              itemFailed = true;
            }
          }
        }

        if (!coverSourceIds.contains(sourceId)) {
          final coverUrl = workInfo['mainCoverUrl']?.toString() ?? '';
          if (coverUrl.isNotEmpty) {
            try {
              final bytes = await api.getCoverBytes(coverUrl);
              if (bytes == null) {
                itemFailed = true;
              } else {
                await cache.saveCover(sourceId, bytes);
                coversFilled++;
              }
            } catch (_) {
              itemFailed = true;
            }
          }
        }

        if (itemFailed) failed++;
        onProgress(CompleteProgress(
          tracksFilled: tracksFilled,
          coversFilled: coversFilled,
          failed: failed,
          currentSourceId: sourceId,
          totalTracksMissing: totalTracksMissing,
          totalCoversMissing: totalCoversMissing,
        ));
      }
    } finally {
      limiter.minInterval = originalInterval;
    }

    return CompleteResult(
      tracksFilled: tracksFilled,
      coversFilled: coversFilled,
      failed: failed,
      cancelled: cancelled,
    );
  }

  Future<Map<String, dynamic>?> _fetchWorkInfoForSource({
    required String sourceId,
    required CacheService cache,
    required AsmrApi api,
  }) async {
    final digits = CacheService.normalizeDigits(sourceId);
    if (digits.isEmpty) return null;
    final data = await api.getWorkInfoOrThrow(digits);
    if (data == null) return null;
    await _saveWorkInfoAliases(cache, sourceId, data);
    return data;
  }

  Future<Map<String, dynamic>?> _fetchWorkInfoCachedOrRemote({
    required String id,
    required CacheService cache,
    required AsmrApi api,
  }) async {
    final cached = await _findCachedWorkInfo(cache, id);
    if (cached != null) return cached;

    final digits = CacheService.normalizeDigits(id);
    if (digits.isEmpty) return null;
    final data = await api.getWorkInfoOrThrow(digits);
    if (data == null) return null;
    await _saveWorkInfoAliases(cache, id, data);
    return data;
  }

  Future<void> _saveWorkInfoAliases(
    CacheService cache,
    String requestedId,
    Map<String, dynamic> data,
  ) async {
    final requested = requestedId.trim();
    if (RegExp(r'^(RJ|VJ|BJ)\d+$', caseSensitive: false).hasMatch(requested)) {
      await cache.saveWorkInfo(requested.toUpperCase(), data);
    } else if (requested.isNotEmpty) {
      final digits = CacheService.normalizeDigits(requested);
      if (digits.isNotEmpty) await cache.saveWorkInfo(digits, data);
    }

    final responseSourceId = data['source_id']?.toString().trim() ?? '';
    if (responseSourceId.isNotEmpty) {
      await cache.saveWorkInfo(responseSourceId.toUpperCase(), data);
    }
  }

  Future<bool> _hasCachedCandidate(
    CacheService cache,
    List<String> candidates,
  ) async {
    for (final candidate in candidates) {
      if (await _findCachedWorkInfo(cache, candidate) != null) return true;
    }
    return false;
  }

  Future<Map<String, dynamic>?> _findCachedWorkInfo(
    CacheService cache,
    String id,
  ) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;
    if (RegExp(r'^(RJ|VJ|BJ)\d+$', caseSensitive: false).hasMatch(trimmed)) {
      return cache.getWorkInfo(trimmed.toUpperCase());
    }
    final sourceId = await cache.findSourceIdByDigits(trimmed);
    if (sourceId == null) return null;
    return cache.getWorkInfo(sourceId);
  }

  String _circleName(Map<String, dynamic> workInfo) {
    final circle = workInfo['circle'];
    if (circle is Map) return circle['name']?.toString().trim() ?? '';
    return '';
  }

  String _workId(Map<String, dynamic> workInfo, String sourceId) {
    final rawId = workInfo['id']?.toString().trim() ?? '';
    return rawId.isNotEmpty ? rawId : CacheService.normalizeDigits(sourceId);
  }

  Map<String, dynamic> _decodeWorkInfo(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // 坏的导入数据仍可继续尝试从 sourceId 补 tracks。
    }
    return const {};
  }
}
