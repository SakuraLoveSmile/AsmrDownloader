import 'dart:typed_data';

import 'package:asmr_downloader/services/asmr_repo/asmr_api.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/api_providers.dart';
import 'package:asmr_downloader/services/cache/cache_complete_service.dart';
import 'package:asmr_downloader/services/cache/cache_database.dart';
import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:asmr_downloader/services/cache/cache_service.dart';
import 'package:asmr_downloader/services/cache/rate_limiter.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCompleteApi extends AsmrApi {
  final Map<String, List<dynamic>?> tracksById;
  final Map<String, Uint8List?> coversByUrl;
  final Set<String> nullTrackIds = {};
  final Set<String> throwingTrackIds = {};
  final Set<String> throwingCoverUrls = {};
  final List<String> trackCalls = [];
  final List<String> coverCalls = [];

  FakeCompleteApi({
    this.tracksById = const {},
    this.coversByUrl = const {},
  });

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
}
