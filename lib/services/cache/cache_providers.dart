import 'package:asmr_downloader/services/cache/batch_cache_service.dart';
import 'package:asmr_downloader/services/cache/cache_database.dart';
import 'package:asmr_downloader/services/cache/cache_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 本地缓存数据库（SQLite/drift）
final cacheDatabaseProvider = Provider<CacheDatabase>((ref) {
  return CacheDatabase();
});

/// 缓存读写服务
final cacheServiceProvider = Provider<CacheService>((ref) {
  return CacheService(ref.watch(cacheDatabaseProvider));
});

/// 强制刷新开关：为 true 时 workInfo/tracks/cover 跳过缓存直连 API。
/// 由搜索框刷新按钮置位，刷新完成后复位（见 SearchBox._refresh）。
final forceRefreshProvider = StateProvider<bool>((ref) => false);

/// 批量缓存服务（主动缓存：按标签/社团/CV 分页拉取 workInfo 写入缓存）
final batchCacheServiceProvider = Provider<BatchCacheService>((ref) {
  return BatchCacheService(ref);
});
