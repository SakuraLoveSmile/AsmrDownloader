import 'dart:convert';

import 'package:asmr_downloader/services/asmr_repo/providers/api_providers.dart';
import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:asmr_downloader/services/cache/cache_service.dart';
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

/// 为已有 workInfo 缓存的作品补全 tracks 和封面缓存。
class CacheCompleteService {
  CacheCompleteService(this.ref);

  final Ref ref;

  /// 补全请求至少使用批量缓存的默认间隔，避免连续补 tracks/封面时过于密集。
  static const Duration completeRunInterval = Duration(seconds: 2);

  Future<CompleteResult> completeMissing({
    required void Function(CompleteProgress) onProgress,
    required bool Function() isCancelled,
  }) async {
    final cache = ref.read(cacheServiceProvider);
    final api = ref.read(asmrApiProvider);
    final limiter = ref.read(rateLimiterProvider);
    final originalInterval = limiter.minInterval;
    if (originalInterval < completeRunInterval) {
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
