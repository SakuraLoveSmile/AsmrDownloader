import 'dart:io';
import 'dart:typed_data';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/asmr_api.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/api_providers.dart';
import 'package:asmr_downloader/services/cache/cache_complete_service.dart';
import 'package:asmr_downloader/services/cache/cache_database.dart';
import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:asmr_downloader/services/cache/cache_service.dart';
import 'package:asmr_downloader/services/cache/rate_limiter.dart';
import 'package:asmr_downloader/services/library/library_database.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class FakeCompleteApi extends AsmrApi {
  final Map<String, List<dynamic>?> tracksById;
  final Map<String, Uint8List?> coversByUrl;
  final Map<String, Map<String, dynamic>?> workInfoById;
  final Set<String> nullTrackIds = {};
  final Set<String> throwingTrackIds = {};
  final Set<String> throwingCoverUrls = {};
  final List<String> trackCalls = [];
  final List<String> coverCalls = [];
  final List<String> workInfoCalls = [];

  FakeCompleteApi({
    this.tracksById = const {},
    this.coversByUrl = const {},
    this.workInfoById = const {},
  });

  @override
  Future<Map<String, dynamic>?> getWorkInfo(String id) async {
    workInfoCalls.add(id);
    return workInfoById[id];
  }

  @override
  Future<List<dynamic>?> getTracks(String id) async {
    trackCalls.add(id);
    if (throwingTrackIds.contains(id)) throw Exception('tracks failed');
    if (nullTrackIds.contains(id)) return null;
    return tracksById[id] ?? <dynamic>[];
  }

  @override
  Future<Uint8List?> getCoverBytes(String url) async {
    coverCalls.add(url);
    if (throwingCoverUrls.contains(url)) throw Exception('cover failed');
    return coversByUrl[url] ?? Uint8List.fromList([1, 2, 3]);
  }
}

void main() {
  Future<(CacheService, FakeCompleteApi, CacheCompleteService)> setup({
    required FakeCompleteApi api,
    Duration interval = Duration.zero,
  }) async {
    final database = CacheDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = CacheService(database);
    final container = ProviderContainer(overrides: [
      cacheServiceProvider.overrideWith((ref) => cache),
      asmrApiProvider.overrideWith((ref) => api),
      rateLimiterProvider
          .overrideWith((ref) => RateLimiter(minInterval: interval)),
    ]);
    addTearDown(container.dispose);
    return (cache, api, container.read(cacheCompleteServiceProvider));
  }

  test('已完整条目跳过且不请求 API', () async {
    final (cache, api, service) = await setup(api: FakeCompleteApi());
    await cache.saveWorkInfo('RJ100', {
      'id': '100',
      'mainCoverUrl': 'https://example.com/100.jpg',
    });
    await cache.saveTracks('RJ100', []);
    await cache.saveCover('RJ100', Uint8List.fromList([1]));

    final result = await service.completeMissing(
      onProgress: (_) {},
      isCancelled: () => false,
    );

    expect(result.tracksFilled, 0);
    expect(result.coversFilled, 0);
    expect(result.failed, 0);
    expect(api.trackCalls, isEmpty);
    expect(api.coverCalls, isEmpty);
  });

  test('缺少 tracks / 封面时分别调用 API 并写入缓存', () async {
    final (cache, api, service) = await setup(
      api: FakeCompleteApi(
        tracksById: {
          '101': [
            {'title': 'track'},
          ]
        },
        coversByUrl: {
          'https://example.com/101.jpg': Uint8List.fromList([1, 2]),
          'https://example.com/102.jpg': Uint8List.fromList([3, 4]),
        },
      ),
    );
    await cache.saveWorkInfo('RJ101', {
      'id': '101',
      'mainCoverUrl': 'https://example.com/101.jpg',
    });
    await cache.saveWorkInfo('RJ102', {
      'id': '102',
      'mainCoverUrl': 'https://example.com/102.jpg',
    });
    await cache.saveWorkInfo('RJ103', {
      'id': '103',
      'mainCoverUrl': 'https://example.com/103.jpg',
    });
    await cache.saveTracks('RJ102', []); // 仅缺封面
    await cache.saveCover('RJ103', Uint8List.fromList([5])); // 仅缺 tracks

    final result = await service.completeMissing(
      onProgress: (_) {},
      isCancelled: () => false,
    );

    expect(result.tracksFilled, 2);
    expect(result.coversFilled, 2);
    expect(result.failed, 0);
    expect(api.trackCalls, ['101', '103']);
    expect(api.coverCalls, [
      'https://example.com/101.jpg',
      'https://example.com/102.jpg',
    ]);
    expect(await cache.getTracks('RJ101'), isNotNull);
    expect(await cache.getTracks('RJ103'), isNotNull);
    expect(await cache.getCover('RJ101'), isNotNull);
    expect(await cache.getCover('RJ102'), isNotNull);
  });

  test('无 id 且 sourceId 无数字时跳过 tracks，空封面 URL 跳过封面', () async {
    final (cache, api, service) = await setup(api: FakeCompleteApi());
    await cache.saveWorkInfo('unknown', {'title': '无数字 id'});
    await cache.saveWorkInfo('RJ200', {'id': '200', 'mainCoverUrl': ''});

    final result = await service.completeMissing(
      onProgress: (_) {},
      isCancelled: () => false,
    );

    expect(result.tracksFilled, 1);
    expect(result.coversFilled, 0);
    expect(result.failed, 0);
    expect(api.trackCalls, ['200']);
    expect(api.coverCalls, isEmpty);
  });

  test('API 返回 null 计失败且不中断后续条目', () async {
    final api = FakeCompleteApi(tracksById: {
      '202': ['ok'],
    });
    api.nullTrackIds.add('201');
    final (cache, _, service) = await setup(api: api);
    await cache.saveWorkInfo('RJ201', {'id': '201'});
    await cache.saveWorkInfo('RJ202', {'id': '202'});

    final result = await service.completeMissing(
      onProgress: (_) {},
      isCancelled: () => false,
    );

    expect(result.tracksFilled, 1);
    expect(result.failed, 1);
    expect(api.trackCalls, ['201', '202']);
  });

  test('取消后停止且还原 minInterval', () async {
    final api = FakeCompleteApi();
    final (cache, _, service) = await setup(
      api: api,
      interval: const Duration(milliseconds: 37),
    );
    await cache.saveWorkInfo('RJ301', {'id': '301'});
    await cache.saveWorkInfo('RJ302', {'id': '302'});
    var cancelled = false;

    final result = await service.completeMissing(
      onProgress: (progress) {
        if (progress.currentSourceId == 'RJ301') cancelled = true;
      },
      isCancelled: () => cancelled,
    );

    expect(result.cancelled, true);
    expect(api.trackCalls, ['301']);
    expect(service.ref.read(rateLimiterProvider).minInterval,
        const Duration(milliseconds: 37));
  });

  group('completeWorksLibrary 作品库补全', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('works_complete_test');
    });

    tearDown(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });

    void createWork(String circle, String dirName, String rj) {
      Directory(p.join(root.path, circle, dirName, rj, '音声'))
          .createSync(recursive: true);
      File(p.join(root.path, circle, dirName, rj, '音声', 'a.wav'))
          .writeAsStringSync('x');
    }

    Future<ProviderContainer> makeWorksContainer({
      required FakeCompleteApi api,
      Duration interval = Duration.zero,
    }) async {
      final cacheDb = CacheDatabase.forTesting(NativeDatabase.memory());
      addTearDown(cacheDb.close);
      final indexDb = LibraryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(indexDb.close);
      final index = WorksIndex(filePath: 'works_index.json', database: indexDb);
      final container = ProviderContainer(overrides: [
        cacheServiceProvider.overrideWith((ref) => CacheService(cacheDb)),
        asmrApiProvider.overrideWith((ref) => api),
        rateLimiterProvider
            .overrideWith((ref) => RateLimiter(minInterval: interval)),
        downloadPathProvider.overrideWith((ref) => root.path),
        navidromePathProvider.overrideWith((ref) => p.join(root.path, 'nav')),
        worksIndexProvider.overrideWith((ref) => index),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('扫描下载根目录补全缓存并回写注册表（保留 dlPath/dirName/organizedAt）', () async {
      createWork('社团A', 'RJ123456 - CV1 - 标题', 'RJ123456');
      createWork('社团B', 'RJ654321 - CV2 - 标题2', 'RJ654321');

      final api = FakeCompleteApi(
        workInfoById: {
          '123456': {
            'source_id': 'RJ123456',
            'id': '123456',
            'title': '在线标题',
            'circle': {'name': '在线社团'},
            'vas': [
              {'name': 'CV_在线'},
            ],
            'release': '2026-06-09',
            'tags': [
              {
                'i18n': {
                  'zh-cn': {'name': '舔耳'}
                }
              },
            ],
            'mainCoverUrl': 'https://example.com/123456.jpg',
          },
          '654321': {
            'source_id': 'RJ654321',
            'id': '654321',
            'title': '标题2',
            'circle': {'name': '社团2'},
            'vas': [
              {'name': 'CV2'},
            ],
            'mainCoverUrl': 'https://example.com/654321.jpg',
          },
        },
        tracksById: {
          '123456': [
            {'title': 't1'},
          ],
          '654321': [
            {'title': 't2'},
          ],
        },
        coversByUrl: {
          'https://example.com/123456.jpg': Uint8List.fromList([1]),
          'https://example.com/654321.jpg': Uint8List.fromList([2]),
        },
      );
      final container = await makeWorksContainer(api: api);
      final service = container.read(cacheCompleteServiceProvider);
      final index = container.read(worksIndexProvider);
      // 注册表已有条目（保留 organizedAt 与路径字段）
      await index.upsert(WorkEntry(
        sourceId: 'RJ123456',
        dlPath: p.join(root.path, '社团A'),
        dirName: 'RJ123456 - CV1 - 标题',
        title: '旧标题',
        cvNames: '旧CV',
        organizedAt: '2026-08-01T00:00:00.000',
      ));

      final result = await service.completeWorksLibrary(
        onProgress: (_) {},
        isCancelled: () => false,
      );

      expect(result.processed, 2);
      expect(result.total, 2);
      expect(result.metadataFilled, 2);
      expect(result.indexFilled, 2);
      expect(result.tracksFilled, 2);
      expect(result.coversFilled, 2);
      expect(result.failed, 0);
      expect(result.cancelled, false);
      expect(api.workInfoCalls, ['123456', '654321']);

      // 缓存已补全
      final cache = container.read(cacheServiceProvider);
      expect(await cache.getWorkInfo('RJ123456'), isNotNull);
      expect(await cache.getTracks('RJ123456'), isNotNull);
      expect(await cache.getCover('RJ123456'), isNotNull);

      // 在线元数据回写注册表；dlPath/dirName/organizedAt 保留
      final entry = (await index.get('RJ123456'))!;
      expect(entry.title, '在线标题');
      expect(entry.cvNames, 'CV_在线');
      expect(entry.circleName, '在线社团');
      expect(entry.releaseDate, '2026-06-09');
      expect(entry.tags, ['舔耳']);
      expect(entry.dlPath, p.join(root.path, '社团A'));
      expect(entry.dirName, 'RJ123456 - CV1 - 标题');
      expect(entry.organizedAt, '2026-08-01T00:00:00.000');

      // 未注册作品也被补全并入库（organizedAt 保持 null）
      final entry2 = (await index.get('RJ654321'))!;
      expect(entry2.title, '标题2');
      expect(entry2.cvNames, 'CV2');
      expect(entry2.dlPath, p.join(root.path, '社团B'));
      expect(entry2.dirName, 'RJ654321 - CV2 - 标题2');
      expect(entry2.organizedAt, isNull);
    });

    test('手动编辑条目不会被覆盖（tracks/封面缓存仍补全）', () async {
      createWork('', 'RJ222222', '');
      // 平铺 RJ 目录：<root>/RJ222222
      final api = FakeCompleteApi(
        workInfoById: {
          '222222': {
            'source_id': 'RJ222222',
            'id': '222222',
            'title': '在线标题',
            'circle': {'name': '在线社团'},
            'vas': [
              {'name': '在线CV'},
            ],
            'mainCoverUrl': 'https://example.com/222222.jpg',
          },
        },
        coversByUrl: {
          'https://example.com/222222.jpg': Uint8List.fromList([9]),
        },
      );
      final container = await makeWorksContainer(api: api);
      final service = container.read(cacheCompleteServiceProvider);
      final index = container.read(worksIndexProvider);
      await index.upsert(WorkEntry(
        sourceId: 'RJ222222',
        dlPath: root.path,
        dirName: '',
        title: '手动标题',
        cvNames: '手动CV',
        circleName: '手动社团',
        releaseDate: '2024-01-01',
        tags: const ['手动标签'],
        manuallyEditedAt: DateTime.parse('2026-08-13T00:00:00.000'),
      ));

      final result = await service.completeWorksLibrary(
        onProgress: (_) {},
        isCancelled: () => false,
      );

      // 缓存被补全，但注册表保留手动值（不回写）
      final cache = container.read(cacheServiceProvider);
      expect(await cache.getWorkInfo('RJ222222'), isNotNull);
      expect(await cache.getTracks('RJ222222'), isNotNull);
      expect(await cache.getCover('RJ222222'), isNotNull);
      expect(result.metadataFilled, 1);
      expect(result.tracksFilled, 1);
      expect(result.coversFilled, 1);
      expect(result.indexFilled, 0);

      final entry = (await index.get('RJ222222'))!;
      expect(entry.title, '手动标题');
      expect(entry.cvNames, '手动CV');
      expect(entry.circleName, '手动社团');
      expect(entry.releaseDate, '2024-01-01');
      expect(entry.tags, ['手动标签']);
      expect(entry.manuallyEditedAt, isNotNull);
    });

    test('全量已缓存且注册表一致：计 skipped 且不回写', () async {
      createWork('社团A', 'RJ333333', '');
      final workInfo = <String, dynamic>{
        'source_id': 'RJ333333',
        'id': '333333',
        'title': '完整标题',
        'circle': {'name': '完整社团'},
        'mainCoverUrl': '',
      };
      final api = FakeCompleteApi(workInfoById: {'333333': workInfo});
      final container = await makeWorksContainer(api: api);
      final service = container.read(cacheCompleteServiceProvider);
      final index = container.read(worksIndexProvider);
      final cache = container.read(cacheServiceProvider);
      // 缓存与注册表均已完整且一致（注册表 cvNames 为空、workInfo 无 vas，
      // 解析结果一致 → 不回写）
      await cache.saveWorkInfo('RJ333333', workInfo);
      await cache.saveTracks('RJ333333', []);
      await cache.saveCover('RJ333333', Uint8List.fromList([1]));
      await index.upsert(WorkEntry(
        sourceId: 'RJ333333',
        dlPath: root.path,
        dirName: '社团A',
        title: '完整标题',
        cvNames: '',
        circleName: '完整社团',
        organizedAt: '2026-08-01T00:00:00.000',
      ));

      final result = await service.completeWorksLibrary(
        onProgress: (_) {},
        isCancelled: () => false,
      );

      expect(result.processed, 1);
      expect(result.metadataFilled, 0);
      expect(result.tracksFilled, 0);
      expect(result.coversFilled, 0);
      expect(result.indexFilled, 0);
      expect(result.skipped, 1);
      expect(result.failed, 0);
      expect(api.workInfoCalls, isEmpty);
    });

    test('取消后停止且还原 minInterval', () async {
      createWork('社团A', 'RJ444444', '');
      createWork('社团B', 'RJ555555', '');
      final api = FakeCompleteApi(
        workInfoById: {
          '444444': {
            'source_id': 'RJ444444',
            'id': '444444',
            'mainCoverUrl': '',
          },
          '555555': {
            'source_id': 'RJ555555',
            'id': '555555',
            'mainCoverUrl': '',
          },
        },
      );
      final container = await makeWorksContainer(
        api: api,
        interval: const Duration(milliseconds: 41),
      );
      final service = container.read(cacheCompleteServiceProvider);
      var cancelled = false;

      final result = await service.completeWorksLibrary(
        onProgress: (progress) {
          if (progress.processed == 1) cancelled = true;
        },
        isCancelled: () => cancelled,
      );

      expect(result.cancelled, true);
      expect(result.processed, 1);
      expect(result.total, 2);
      expect(container.read(rateLimiterProvider).minInterval,
          const Duration(milliseconds: 41));
    });

    test('扁平作品补全后 sourceDirOverride / sourceDir 保持不变', () async {
      // 扁平结构：<root>/RJ777777 - CV7 - 标题7/a.wav（无内层 RJ 目录）
      final flatDir = Directory(p.join(root.path, 'RJ777777 - CV7 - 标题7'))
        ..createSync(recursive: true);
      File(p.join(flatDir.path, 'a.wav')).writeAsStringSync('x');

      final api = FakeCompleteApi(
        workInfoById: {
          '777777': {
            'source_id': 'RJ777777',
            'id': '777777',
            'title': '在线标题7',
            'circle': {'name': '社团7'},
            'vas': [
              {'name': 'CV7'},
            ],
            'mainCoverUrl': 'https://example.com/777777.jpg',
          },
        },
        coversByUrl: {
          'https://example.com/777777.jpg': Uint8List.fromList([7]),
        },
      );
      final container = await makeWorksContainer(api: api);
      final service = container.read(cacheCompleteServiceProvider);
      final index = container.read(worksIndexProvider);

      final result = await service.completeWorksLibrary(
        onProgress: (_) {},
        isCancelled: () => false,
      );

      expect(result.processed, 1);
      expect(result.metadataFilled, 1);
      expect(result.indexFilled, 1);
      // 在线元数据回写，同时保留 override 与路径字段
      final entry = (await index.get('RJ777777'))!;
      expect(entry.sourceDirOverride, flatDir.path);
      expect(entry.sourceDir, flatDir.path);
      expect(entry.dirName, 'RJ777777 - CV7 - 标题7');
      expect(entry.dlPath, root.path);
      expect(entry.title, '在线标题7');
      // 缓存照常补全
      final cache = container.read(cacheServiceProvider);
      expect(await cache.getWorkInfo('RJ777777'), isNotNull);
      expect(await cache.getTracks('RJ777777'), isNotNull);
      expect(await cache.getCover('RJ777777'), isNotNull);
    });
  });
}
