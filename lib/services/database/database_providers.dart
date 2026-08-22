import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:asmr_downloader/services/library/library_database_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 两个 SQLite 数据库的轻量统计，用于数据库页面展示。
class DatabaseOverview {
  const DatabaseOverview({
    required this.cachePath,
    required this.libraryPath,
    required this.workInfoCount,
    required this.tracksCount,
    required this.coverCount,
    required this.libraryWorkCount,
    required this.libraryLocationCount,
    required this.libraryRootCount,
  });

  final String cachePath;
  final String libraryPath;
  final int workInfoCount;
  final int tracksCount;
  final int coverCount;
  final int libraryWorkCount;
  final int libraryLocationCount;
  final int libraryRootCount;

  int get cachedDataCount => workInfoCount + tracksCount + coverCount;
}

/// 读取数据库页面所需统计；不会加载 tracks JSON 或封面 BLOB。
final databaseOverviewProvider = FutureProvider<DatabaseOverview>((ref) async {
  final cache = ref.watch(cacheServiceProvider);
  final library = ref.watch(libraryDatabaseProvider);

  final counts = await Future.wait<int>([
    cache.getCacheCount(),
    cache.getTracksCount(),
    cache.getCoverCount(),
    library.select(library.libraryWorks).get().then((rows) => rows.length),
    library
        .select(library.mediaLibraryLocations)
        .get()
        .then((rows) => rows.length),
    library.select(library.mediaLibraryRoots).get().then((rows) => rows.length),
  ]);

  return DatabaseOverview(
    cachePath: cache.dbPath,
    libraryPath: library.dbFilePath,
    workInfoCount: counts[0],
    tracksCount: counts[1],
    coverCount: counts[2],
    libraryWorkCount: counts[3],
    libraryLocationCount: counts[4],
    libraryRootCount: counts[5],
  );
});
