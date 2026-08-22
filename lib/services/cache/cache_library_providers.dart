import 'dart:convert';
import 'dart:typed_data';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/cache/cache_database.dart';
import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:asmr_downloader/services/cache/cache_service.dart';
import 'package:asmr_downloader/services/library/media_library_service.dart';
import 'package:asmr_downloader/services/organize/navidrome_organizer.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 媒体库中的一个本地缓存作品。
class CachedLibraryEntry {
  const CachedLibraryEntry({
    required this.sourceId,
    required this.cachedAt,
    required this.workInfo,
    required this.hasTracks,
    required this.hasCover,
    this.resolvedCircleName = '',
    this.translationCircleName = '',
    this.locations = const [],
  });

  final String sourceId;
  final DateTime cachedAt;
  final Map<String, dynamic> workInfo;
  final bool hasTracks;
  final bool hasCover;

  /// 解析后的主社团名。简体中文版优先使用日文原版社团。
  final String resolvedCircleName;

  /// 当前作品的翻译社团名；仅在它与主社团不同时展示。
  final String translationCircleName;

  /// 轻量扫描发现的目录位置；一个作品可能同时存在于本机和 NAS。
  final List<MediaLibraryLocationItem> locations;

  String get title => _readString(workInfo['title']).isEmpty
      ? sourceId
      : _readString(workInfo['title']);

  String get sourceCircleName {
    final circle = workInfo['circle'];
    if (circle is! Map) return '';
    return _readString(circle['name']);
  }

  /// 媒体库分类使用的主社团名。
  String get circleName => resolvedCircleName.trim().isNotEmpty
      ? resolvedCircleName.trim()
      : sourceCircleName;

  List<String> get cvNames => _readNames(workInfo['vas']);

  String get releaseDate => _readString(workInfo['release']);

  String get dlCount => _readString(workInfo['dl_count']);

  bool get hasMetadata => workInfo.isNotEmpty;

  int get locationCount => locations.length;

  String get locationSummary {
    if (locations.isEmpty) return '未记录位置';
    if (locations.length == 1) return locations.single.matchedPath;
    return '${locations.length} 个位置';
  }

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

/// 媒体库的浏览方式。
///
/// `cv` 模式下，一个作品可以同时出现在多个 CV 分组中，方便按声优
/// 浏览合作作品；没有元数据的作品会进入「未关联」分组。
enum MediaLibraryGroupBy {
  none,
  circle,
  cv,
}

/// 全部缓存作品及 tracks / 封面存在性索引。
final cachedLibraryProvider = FutureProvider<CachedLibrary>((ref) async {
  final cache = ref.watch(cacheServiceProvider);
  final mediaLibrary = ref.watch(mediaLibraryServiceProvider);
  final registryEntries = await ref.watch(worksIndexProvider).list();
  final registryById = <String, WorkEntry>{
    for (final entry in registryEntries) entry.sourceId: entry,
  };

  // 目录扫描只返回作品级 sourceId，文件数量/字幕/封面等明细不在这里扫描。
  await mediaLibrary.scanConfiguredRoots();
  final locations = await mediaLibrary.listLocations(
    roots: ref.watch(mediaLibraryRootsProvider),
  );
  final locationsById = <String, List<MediaLibraryLocationItem>>{};
  for (final location in locations) {
    locationsById.putIfAbsent(location.sourceId, () => []).add(location);
  }

  // 启动三个查询后再等待，避免列表数据和两个存在性索引串行读取。
  final workInfoFuture = cache.listWorkInfoEntries();
  final tracksFuture = cache.listTracksSourceIds();
  final coversFuture = cache.listCoverSourceIds();
  final workInfoEntries = await workInfoFuture;
  final tracksSourceIds = await tracksFuture;
  final coverSourceIds = await coversFuture;

  final workInfoById = <String, WorkInfoEntry>{
    for (final row in workInfoEntries) row.sourceId: row,
  };
  final sourceIds = locationsById.keys.toList()..sort();
  final entries = <CachedLibraryEntry>[];
  for (final sourceId in sourceIds) {
    final row = workInfoById[sourceId];
    final workInfo = _mergeWorkInfo(
      row == null ? const {} : _decodeWorkInfo(row.workInfoJson),
      registryById[sourceId],
    );
    // 这里只查本地缓存，不因打开媒体库而隐式联网。点击“一键补全”后，
    // 原版 workInfo 会被缓存，下一次扫描即可稳定按原版社团归类。
    final circleNames = await _resolveCachedCircleNames(cache, workInfo);
    entries.add(
      CachedLibraryEntry(
        sourceId: sourceId,
        // 未缓存元数据的作品仍显示在媒体库中，时间以扫描时间为准。
        cachedAt: row?.cachedAt ?? locationsById[sourceId]!.first.scannedAt,
        workInfo: workInfo,
        hasTracks: tracksSourceIds.contains(sourceId),
        hasCover: coverSourceIds.contains(sourceId),
        resolvedCircleName: circleNames.primary,
        translationCircleName: circleNames.translation,
        locations: List.unmodifiable(locationsById[sourceId]!),
      ),
    );
  }
  return CachedLibrary(List.unmodifiable(entries));
});

Future<ResolvedCircleNames> _resolveCachedCircleNames(
  CacheService cache,
  Map<String, dynamic> workInfo,
) async {
  final fallback = _readCircleName(workInfo);
  return NavidromeOrganizer.resolveCircleNames(
    workInfo: workInfo,
    fallbackCircle: fallback,
    fetchWorkInfo: (id) => _getCachedWorkInfo(cache, id),
  );
}

Future<Map<String, dynamic>?> _getCachedWorkInfo(
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

/// 按作品懒加载封面 BLOB；provider 本身会复用 Riverpod 的结果缓存。
final cachedCoverProvider = FutureProvider.family<Uint8List?, String>(
  (ref, sourceId) => ref.watch(cacheServiceProvider).getCover(sourceId),
);

final cacheSearchQueryProvider = StateProvider<String>((ref) => '');

final cacheSortProvider = StateProvider<CacheSort>((ref) => CacheSort.cachedAt);

/// 媒体库分组方式：平铺、按社团、按 CV。
final mediaLibraryGroupByProvider =
    StateProvider<MediaLibraryGroupBy>((ref) => MediaLibraryGroupBy.none);

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

/// 优先使用 API 缓存，同时用作品索引数据库补齐标题、社团和 CV。
///
/// 这样即使用户清理过 workInfo 缓存，媒体库仍能按已有的本地数据库元数据
/// 分类；API 返回的字段始终优先，不会被旧注册表覆盖。
Map<String, dynamic> _mergeWorkInfo(
  Map<String, dynamic> cached,
  WorkEntry? registry,
) {
  if (registry == null) return cached;
  final merged = Map<String, dynamic>.of(cached);

  if (_readString(merged['title']).isEmpty && registry.title.isNotEmpty) {
    merged['title'] = registry.title;
  }
  if (_readCircleName(merged).isEmpty && registry.circleName.isNotEmpty) {
    merged['circle'] = {'name': registry.circleName};
  }
  if (_readNames(merged['vas']).isEmpty && registry.cvNames.isNotEmpty) {
    merged['vas'] = registry.cvNames
        .split('&')
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .map((name) => {'name': name})
        .toList();
  }
  if (_readString(merged['release']).isEmpty &&
      registry.releaseDate.isNotEmpty) {
    merged['release'] = registry.releaseDate;
  }
  if ((merged['tags'] is! List || (merged['tags'] as List).isEmpty) &&
      registry.tags.isNotEmpty) {
    merged['tags'] = registry.tags
        .map((tag) => {
              'i18n': {
                'zh-cn': {'name': tag},
              },
            })
        .toList();
  }
  return merged;
}

String _readCircleName(Map<String, dynamic> workInfo) {
  final circle = workInfo['circle'];
  return circle is Map ? _readString(circle['name']) : '';
}

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
    entry.sourceCircleName,
    entry.translationCircleName,
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
