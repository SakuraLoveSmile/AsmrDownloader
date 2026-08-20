import 'package:asmr_downloader/services/asmr_repo/asmr_api.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/api_providers.dart';
import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 批量缓存进度（UI 推送用）
class BatchCacheProgress {
  final int cached; // 本次新缓存数
  final int skipped; // 已缓存跳过数
  final int failed; // 失败数
  final String currentSourceId;
  final int? total; // 本次批量预计总数（来自 pagination.totalCount，首个搜索页确定）
  final bool totalApprox; // total 是否为近似值（circle/va 降级普通搜索时的差异）

  const BatchCacheProgress({
    required this.cached,
    required this.skipped,
    required this.failed,
    required this.currentSourceId,
    this.total,
    this.totalApprox = false,
  });
}

/// 批量缓存汇总结果
class BatchCacheResult {
  final int cached;
  final int skipped;
  final int failed;
  final bool cancelled;
  final int? total; // 预计总数（可能为近似值）
  final List<String> failedSourceIds; // 失败作品的 sourceId 列表

  const BatchCacheResult({
    required this.cached,
    required this.skipped,
    required this.failed,
    required this.cancelled,
    this.total,
    this.failedSourceIds = const [],
  });
}

/// 搜索维度
enum BatchCacheDimension { tag, circle, va }

/// 批量缓存编排层：
/// 按维度分页搜索作品列表，逐个请求 workInfo 并写入本地缓存；
/// 已缓存的作品自动跳过；所有 API 请求受全局 RateLimiter 限速。
/// 仅缓存 workInfo 元数据（不拉 tracks 和 cover）。
class BatchCacheService {
  final Ref ref;
  BatchCacheService(this.ref);

  /// 批量缓存默认限速间隔（用户未选择时）
  static const Duration defaultRunInterval = Duration(seconds: 2);

  /// 统一入口
  ///
  /// [runInterval] 为本次批量期间使用的请求间隔（默认 [defaultRunInterval]）。
  /// 开始前临时把全局 RateLimiter 的间隔改为它，结束后还原为用户选择前的值，
  /// 避免影响后续普通搜索/下载请求的节奏。
  Future<BatchCacheResult> batchCache(
    BatchCacheDimension dimension,
    String name, {
    Duration? runInterval,
    required void Function(BatchCacheProgress) onProgress,
    required bool Function() isCancelled,
  }) async {
    final cache = ref.read(cacheServiceProvider);
    final api = ref.read(asmrApiProvider);
    final limiter = ref.read(rateLimiterProvider);
    final originalInterval = limiter.minInterval;
    if (runInterval != null) limiter.minInterval = runInterval;

    int page = 1;
    const pageSize = 30;
    int cached = 0, skipped = 0, failed = 0;
    final failedSourceIds = <String>[];
    bool cancelled = false;
    int? total; // 首个搜索页的 pagination.totalCount
    bool totalApprox = false; // circle/va 降级搜索时 total 可能偏大（含无关题）

    try {
      while (!cancelled) {
        // 1. 分页搜索（circle/va 维度会在服务端搜索后做客户端精确过滤）
        final result = await _searchPage(api, dimension, name, page, pageSize);
        if (result == null) break;
        final rawWorks = (result['works'] as List?) ?? [];
        if (rawWorks.isEmpty) break;

        // 首个搜索页确定预计总数；circle/va 降级为普通搜索，totalCount 偏大为近似
        if (page == 1) {
          final pagination = result['pagination'];
          if (pagination is Map) {
            final t = pagination['totalCount'];
            total = (t is num) ? t.toInt() : null;
          }
          totalApprox = dimension != BatchCacheDimension.tag;
        }

        final works = dimension == BatchCacheDimension.tag
            ? rawWorks
            : rawWorks
                .where((w) => _matchesDimension(w, dimension, name))
                .toList();

        // 2. 逐个获取 workInfo 并缓存
        for (final work in works) {
          if (isCancelled()) {
            cancelled = true;
            break;
          }

          final sourceId = work['source_id']?.toString() ?? '';
          if (sourceId.isEmpty) continue;

          // 已缓存则跳过
          if (await cache.getWorkInfo(sourceId) != null) {
            skipped++;
            onProgress(BatchCacheProgress(
              cached: cached,
              skipped: skipped,
              failed: failed,
              currentSourceId: sourceId,
              total: total,
              totalApprox: totalApprox,
            ));
            continue;
          }

          // 请求 API（经过 RateLimiter 自动限速）
          final id = work['id']?.toString() ?? '';
          try {
            final workInfo = await api.getWorkInfo(id);
            if (workInfo != null) {
              await cache.saveWorkInfo(sourceId, workInfo);
              cached++;
            } else {
              failed++;
              failedSourceIds.add(sourceId);
            }
          } catch (e) {
            failed++;
            failedSourceIds.add(sourceId);
          }

          onProgress(BatchCacheProgress(
            cached: cached,
            skipped: skipped,
            failed: failed,
            currentSourceId: sourceId,
            total: total,
            totalApprox: totalApprox,
          ));
        }

        page++;
        if (rawWorks.length < pageSize) break; // 最后一页（用原始条数判断，避免中段空页提前结束）
      }
    } finally {
      // 还原全局限速间隔，避免影响批量之后的普通请求
      limiter.minInterval = originalInterval;
    }

    return BatchCacheResult(
      cached: cached,
      skipped: skipped,
      failed: failed,
      cancelled: cancelled,
      total: total,
      failedSourceIds: failedSourceIds,
    );
  }

  /// 根据维度调用对应的搜索 API。
  ///
  /// tag 用服务端高级语法 `$tag:name$`（可靠支持）；circle / va 的 `$circle:` /
  /// `$va:` 语法在部分 API 通道上返回为空，因此降级为通用关键词搜索
  /// `search(content: name)`，再在 [batchCache] 里用 [_matchesDimension] 精确过滤
  /// works（按 circle 名 / VA 名匹配），避免把同名作品夹带走。
  Future<Map<String, dynamic>?> _searchPage(
    AsmrApi api,
    BatchCacheDimension dim,
    String name,
    int page,
    int pageSize,
  ) {
    final params = {'page': page, 'pageSize': pageSize};
    switch (dim) {
      case BatchCacheDimension.tag:
        return api.searchByTag(tagName: name, params: params);
      case BatchCacheDimension.circle:
        return api.search(content: name, params: params);
      case BatchCacheDimension.va:
        return api.search(content: name, params: params);
    }
  }

  /// 判断单个 work 是否精确命中 circle / va 维度（用于服务端不支持 `$circle:`/`$va:`
  /// 时的降级过滤）。大小写不敏感、子串包含即命中。
  bool _matchesDimension(
    Object? workObj,
    BatchCacheDimension dim,
    String name,
  ) {
    final work = (workObj is Map) ? workObj : null;
    if (work == null || name.isEmpty) return false;
    final target = name.toLowerCase();

    if (dim == BatchCacheDimension.circle) {
      final circleName =
          (work['circle'] is Map) ? (work['circle'] as Map)['name']?.toString() : null;
      final name2 = work['name']?.toString(); // 部分响应用顶层 name 表示社团名
      return circleName?.toLowerCase().contains(target) == true ||
          name2?.toLowerCase().contains(target) == true;
    }

    // va：作品 vas 列表中任意声优名命中即可
    final vas = work['vas'];
    if (vas is List) {
      for (final va in vas) {
        final vaName =
            (va is Map) ? va['name']?.toString() : va?.toString();
        if (vaName != null && vaName.toLowerCase().contains(target)) return true;
      }
    }
    return false;
  }
}
