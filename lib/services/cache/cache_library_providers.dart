import 'dart:convert';
import 'dart:typed_data';

import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 媒体库中的一个本地缓存作品。
class CachedLibraryEntry {
  const CachedLibraryEntry({
    required this.sourceId,
    required this.cachedAt,
    required this.workInfo,
    required this.hasTracks,
    required this.hasCover,
  });

  final String sourceId;
  final DateTime cachedAt;
  final Map<String, dynamic> workInfo;
  final bool hasTracks;
  final bool hasCover;

  String get title => _readString(workInfo['title']).isEmpty
      ? sourceId
      : _readString(workInfo['title']);

  String get circleName {
    final circle = workInfo['circle'];
    if (circle is! Map) return '';
    return _readString(circle['name']);
  }

  List<String> get cvNames => _readNames(workInfo['vas']);

  String get releaseDate => _readString(workInfo['release']);

  String get dlCount => _readString(workInfo['dl_count']);

  List<String> get tags {
    final rawTags = workInfo['tags'];
    if (rawTags is! List) return const [];
    return rawTags
        .map((tag) {
          if (tag is! Map) return '';
          final i18n = tag['i18n'];
          if (i18n is! Map) return '';
          final zh = i18n['zh-cn'];
          if (zh is! Map) return '';
          return _readString(zh['name']);
        })
        .where((tag) => tag.isNotEmpty)
        .toList();
  }
}

class CachedLibrary {
  const CachedLibrary(this.entries);

  final List<CachedLibraryEntry> entries;
}

enum CacheSort {
  cachedAt,
  releaseDate,
  title,
}

/// 全部缓存作品及 tracks / 封面存在性索引。
final cachedLibraryProvider = FutureProvider<CachedLibrary>((ref) async {
  final cache = ref.watch(cacheServiceProvider);

  // 启动三个查询后再等待，避免列表数据和两个存在性索引串行读取。
  final workInfoFuture = cache.listWorkInfoEntries();
  final tracksFuture = cache.listTracksSourceIds();
  final coversFuture = cache.listCoverSourceIds();
  final workInfoEntries = await workInfoFuture;
  final tracksSourceIds = await tracksFuture;
  final coverSourceIds = await coversFuture;

  final entries = <CachedLibraryEntry>[];
  for (final row in workInfoEntries) {
    entries.add(
      CachedLibraryEntry(
        sourceId: row.sourceId,
        cachedAt: row.cachedAt,
        workInfo: _decodeWorkInfo(row.workInfoJson),
        hasTracks: tracksSourceIds.contains(row.sourceId),
        hasCover: coverSourceIds.contains(row.sourceId),
      ),
    );
  }
  return CachedLibrary(List.unmodifiable(entries));
});

/// 按作品懒加载封面 BLOB；provider 本身会复用 Riverpod 的结果缓存。
final cachedCoverProvider = FutureProvider.family<Uint8List?, String>(
  (ref, sourceId) => ref.watch(cacheServiceProvider).getCover(sourceId),
);

final cacheSearchQueryProvider = StateProvider<String>((ref) => '');

final cacheSortProvider = StateProvider<CacheSort>((ref) => CacheSort.cachedAt);

/// 媒体库的客户端过滤和排序结果。
final filteredCachedLibraryProvider =
    Provider<AsyncValue<List<CachedLibraryEntry>>>((ref) {
  final library = ref.watch(cachedLibraryProvider);
  final query = ref.watch(cacheSearchQueryProvider).trim().toLowerCase();
  final sort = ref.watch(cacheSortProvider);

  return library.whenData((library) {
    final entries = library.entries;
    final filtered = query.isEmpty
        ? List<CachedLibraryEntry>.of(entries)
        : entries.where((entry) => _matchesQuery(entry, query)).toList();
    _sortEntries(filtered, sort);
    return filtered;
  });
});

Map<String, dynamic> _decodeWorkInfo(String rawJson) {
  try {
    final decoded = jsonDecode(rawJson);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {
    // 缓存可能来自旧版本或手工导入，坏数据仍应显示 sourceId 卡片。
  }
  return const {};
}

String _readString(Object? value) => value?.toString() ?? '';

List<String> _readNames(Object? value) {
  if (value is! List) return const [];
  return value
      .map((item) => item is Map ? _readString(item['name']) : '')
      .where((name) => name.isNotEmpty)
      .toList();
}

bool _matchesQuery(CachedLibraryEntry entry, String query) {
  final fields = <String>[
    entry.sourceId,
    entry.title,
    entry.circleName,
    ...entry.cvNames,
  ];
  return fields.any((field) => field.toLowerCase().contains(query));
}

void _sortEntries(List<CachedLibraryEntry> entries, CacheSort sort) {
  switch (sort) {
    case CacheSort.cachedAt:
      entries.sort((a, b) => b.cachedAt.compareTo(a.cachedAt));
    case CacheSort.releaseDate:
      entries.sort((a, b) {
        final aDate = DateTime.tryParse(a.releaseDate);
        final bDate = DateTime.tryParse(b.releaseDate);
        if (aDate == null && bDate == null) {
          return _emptyLastCompare(a.releaseDate, b.releaseDate);
        }
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });
    case CacheSort.title:
      entries.sort((a, b) => a.title.toLowerCase().compareTo(
            b.title.toLowerCase(),
          ));
  }
}

int _emptyLastCompare(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 0;
  if (a.isEmpty) return 1;
  if (b.isEmpty) return -1;
  return b.compareTo(a);
}
