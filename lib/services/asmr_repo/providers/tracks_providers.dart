import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/api_providers.dart';
import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 缓存优先的原始 tracks 树：命中本地缓存则不再请求 API；
/// 未命中（或 forceRefresh）时请求 API 并写入缓存。
/// 文件树结构（hash/URL/大小）发布后固定，适合长期缓存。
final rawTracksProvider = FutureProvider<List<dynamic>?>((ref) async {
  final id = ref.watch(idProvider);
  if (id == null) {
    return null;
  }

  final sourceId = ref.watch(sourceIdProvider) ?? '';
  final cache = ref.read(cacheServiceProvider);
  final forceRefresh = ref.read(forceRefreshProvider);

  if (!forceRefresh && sourceId.isNotEmpty) {
    final cached = await cache.getTracks(sourceId);
    if (cached != null) {
      Log.info('tracks cache hit: $sourceId');
      return cached;
    }
  }

  Log.info('fetch tracks, id: $id');
  final api = ref.watch(asmrApiProvider);
  final data = await api.getTracksOrThrow(id);
  if (data != null && sourceId.isNotEmpty) {
    await cache.saveTracks(sourceId, data);
  }
  return data;
});
