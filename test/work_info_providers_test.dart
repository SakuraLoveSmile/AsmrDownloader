import 'dart:typed_data';

import 'package:asmr_downloader/services/asmr_repo/asmr_api.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/api_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/tracks_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/work_info_providers.dart';
import 'package:asmr_downloader/services/cache/cache_database.dart';
import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:asmr_downloader/services/cache/cache_service.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 记录每次 API 调用的替身（getWorkInfo 记录数字 id，getCoverBytes 记录 cover:url）
class CountingApi extends AsmrApi {
  final List<String> calls;
  CountingApi(this.calls);

  @override
  Future<Map<String, dynamic>?> getWorkInfo(String id) async {
    calls.add(id);
    return {
      'title': 'API 标题',
      'circle': {'name': 'API 社团'},
      'mainCoverUrl': 'https://example.com/cover.jpg',
    };
  }

  @override
  Future<Uint8List?> getCoverBytes(String url) async {
    calls.add('cover:$url');
    return Uint8List.fromList([1, 2, 3]);
  }
}

void main() {
  Map<String, dynamic> fullWorkInfo() => {
        'title': '正式标题',
        'circle': {'name': '社团'},
        'vas': [
          {'name': 'CV1'}
        ],
        'tags': [
          {'i18n': {'zh-cn': {'name': '舔耳'}}}
        ],
        'mainCoverUrl': '',
        'release': '2026-06-09',
        'dl_count': 1,
      };

  /// 构造带 workTitle 的 tracks 树（与 asmr api 实际结构一致）
  List<dynamic> tracksWithWorkTitle(String title) => [
        {
          'type': 'folder',
          'title': 'RJ01619789',
          'children': [
            {'type': 'audio', 'title': 'x.wav', 'workTitle': title},
          ],
        },
      ];

  ProviderContainer makeContainer({
    Map<String, dynamic>? workInfo,
    List<dynamic>? tracks,
    List<String> treePath = const [],
  }) {
    final container = ProviderContainer(overrides: [
      sourceIdProvider.overrideWith((ref) => 'RJ01619789'),
      workInfoProvider.overrideWith((ref) async => workInfo),
      rawTracksProvider.overrideWith((ref) async => tracks),
      workTreePathProvider.overrideWith((ref) => treePath),
    ]);
    return container;
  }

  test('work info 成功时使用 work info 标题', () async {
    final container = makeContainer(workInfo: fullWorkInfo());
    addTearDown(container.dispose);

    await container.read(workInfoProvider.future);
    await container.read(rawTracksProvider.future);

    expect(container.read(titleProvider), '正式标题');
  });

  test('work info 失败时降级到 tracks 携带的 workTitle', () async {
    final container = makeContainer(
      workInfo: null,
      tracks: tracksWithWorkTitle('音轨标题'),
    );
    addTearDown(container.dispose);

    await container.read(workInfoProvider.future);
    await container.read(rawTracksProvider.future);

    expect(container.read(titleProvider), '音轨标题');
  });

  test('work info/tracks 都失败时降级到 URL 目录面包屑', () async {
    final container = makeContainer(
      workInfo: null,
      tracks: null,
      treePath: ['RJ01619789', '舔耳ONLY音轨'],
    );
    addTearDown(container.dispose);

    await container.read(workInfoProvider.future);
    await container.read(rawTracksProvider.future);

    expect(container.read(titleProvider), '舔耳ONLY音轨');
  });

  test('所有数据源都失败时保底 sourceId', () async {
    final container = makeContainer(workInfo: null, tracks: null);
    addTearDown(container.dispose);

    await container.read(workInfoProvider.future);
    await container.read(rawTracksProvider.future);

    expect(container.read(titleProvider), 'RJ01619789');
  });

  test('work info 标题为空字符串时继续降级', () async {
    final container = makeContainer(
      workInfo: {'title': ''},
      tracks: tracksWithWorkTitle('音轨标题'),
    );
    addTearDown(container.dispose);

    await container.read(workInfoProvider.future);
    await container.read(rawTracksProvider.future);

    expect(container.read(titleProvider), '音轨标题');
  });

  group('本地缓存优先', () {
    ProviderContainer makeCacheContainer({
      required List<String> apiCalls,
      required CacheService cache,
      bool forceRefresh = false,
    }) {
      final container = ProviderContainer(overrides: [
        idProvider.overrideWith((ref) => '1619789'),
        sourceIdProvider.overrideWith((ref) => 'RJ01619789'),
        asmrApiProvider.overrideWith((ref) => CountingApi(apiCalls)),
        cacheServiceProvider.overrideWith((ref) => cache),
      ]);
      if (forceRefresh) {
        container.read(forceRefreshProvider.notifier).state = true;
      }
      return container;
    }

    test('workInfo 缓存命中时不调用 API', () async {
      final apiCalls = <String>[];
      final cacheDb = CacheDatabase.forTesting(NativeDatabase.memory());
      addTearDown(cacheDb.close);
      final cache = CacheService(cacheDb);
      await cache.saveWorkInfo('RJ01619789', fullWorkInfo());

      final container =
          makeCacheContainer(apiCalls: apiCalls, cache: cache);
      addTearDown(container.dispose);

      final data = await container.read(workInfoProvider.future);
      expect(data?['title'], '正式标题');
      expect(apiCalls, isEmpty);
    });

    test('workInfo 缓存未命中时请求 API 并写入缓存', () async {
      final apiCalls = <String>[];
      final cacheDb = CacheDatabase.forTesting(NativeDatabase.memory());
      addTearDown(cacheDb.close);
      final cache = CacheService(cacheDb);

      final container =
          makeCacheContainer(apiCalls: apiCalls, cache: cache);
      addTearDown(container.dispose);

      final data = await container.read(workInfoProvider.future);
      expect(data?['title'], 'API 标题');
      expect(apiCalls, ['1619789']);
      // 已写缓存，再次读取不请求 API
      expect((await cache.getWorkInfo('RJ01619789'))?['title'], 'API 标题');
    });

    test('forceRefresh 时跳过缓存重新请求 API 并覆盖缓存', () async {
      final apiCalls = <String>[];
      final cacheDb = CacheDatabase.forTesting(NativeDatabase.memory());
      addTearDown(cacheDb.close);
      final cache = CacheService(cacheDb);
      await cache.saveWorkInfo('RJ01619789', fullWorkInfo());

      final container = makeCacheContainer(
          apiCalls: apiCalls, cache: cache, forceRefresh: true);
      addTearDown(container.dispose);

      final data = await container.read(workInfoProvider.future);
      expect(data?['title'], 'API 标题');
      expect(apiCalls, ['1619789']);
      expect((await cache.getWorkInfo('RJ01619789'))?['title'], 'API 标题');
    });

    test('rawTracksProvider 缓存命中时不调用 API', () async {
      final apiCalls = <String>[];
      final cacheDb = CacheDatabase.forTesting(NativeDatabase.memory());
      addTearDown(cacheDb.close);
      final cache = CacheService(cacheDb);
      await cache.saveTracks('RJ01619789', [
        {'title': '缓存音轨.wav'},
      ]);

      final container =
          makeCacheContainer(apiCalls: apiCalls, cache: cache);
      addTearDown(container.dispose);

      final tracks = await container.read(rawTracksProvider.future);
      expect(tracks, hasLength(1));
      expect((tracks![0] as Map)['title'], '缓存音轨.wav');
      expect(apiCalls, isEmpty);
    });

    test('coverBytesProvider 缓存命中时不请求封面', () async {
      final apiCalls = <String>[];
      final cacheDb = CacheDatabase.forTesting(NativeDatabase.memory());
      addTearDown(cacheDb.close);
      final cache = CacheService(cacheDb);
      await cache.saveCover('RJ01619789', Uint8List.fromList([9, 9]));

      final container = ProviderContainer(overrides: [
        idProvider.overrideWith((ref) => '1619789'),
        sourceIdProvider.overrideWith((ref) => 'RJ01619789'),
        workInfoProvider.overrideWith((ref) async => {
          'title': 't',
          'mainCoverUrl': 'https://example.com/cover.jpg',
        }),
        asmrApiProvider.overrideWith((ref) => CountingApi(apiCalls)),
        cacheServiceProvider.overrideWith((ref) => cache),
      ]);
      addTearDown(container.dispose);

      // 先等 workInfo 解析出封面 URL（与 UI 实际渲染顺序一致），
      // 否则 coverUrlProvider 在 workInfo loading 期间会返回空串
      await container.read(workInfoProvider.future);
      final bytes = await container.read(coverBytesProvider.future);
      expect(bytes, Uint8List.fromList([9, 9]));
      expect(apiCalls, isEmpty);
    });

    test('coverBytesProvider 未命中时请求并写缓存', () async {
      final apiCalls = <String>[];
      final cacheDb = CacheDatabase.forTesting(NativeDatabase.memory());
      addTearDown(cacheDb.close);
      final cache = CacheService(cacheDb);

      final container = ProviderContainer(overrides: [
        idProvider.overrideWith((ref) => '1619789'),
        sourceIdProvider.overrideWith((ref) => 'RJ01619789'),
        workInfoProvider.overrideWith((ref) async => {
          'title': 't',
          'mainCoverUrl': 'https://example.com/cover.jpg',
        }),
        asmrApiProvider.overrideWith((ref) => CountingApi(apiCalls)),
        cacheServiceProvider.overrideWith((ref) => cache),
      ]);
      addTearDown(container.dispose);

      await container.read(workInfoProvider.future);
      final bytes = await container.read(coverBytesProvider.future);
      expect(bytes, Uint8List.fromList([1, 2, 3]));
      expect(apiCalls, ['cover:https://example.com/cover.jpg']);
      expect(await cache.getCover('RJ01619789'), Uint8List.fromList([1, 2, 3]));
    });
  });

  group('findWorkTitleInTracks', () {
    test('null 返回 null', () {
      expect(findWorkTitleInTracks(null), isNull);
    });

    test('空列表返回 null', () {
      expect(findWorkTitleInTracks([]), isNull);
    });

    test('递归查找嵌套节点的 workTitle', () {
      final found = findWorkTitleInTracks(tracksWithWorkTitle('嵌套标题'));
      expect(found, '嵌套标题');
    });

    test('workTitle 为空时继续深入', () {
      final tracks = [
        {
          'type': 'folder',
          'title': 'r',
          'children': [
            {'type': 'audio', 'title': 'a', 'workTitle': ''},
            {'type': 'text', 'title': 'b', 'workTitle': '真实标题'},
          ],
        },
      ];
      expect(findWorkTitleInTracks(tracks), '真实标题');
    });
  });
}
