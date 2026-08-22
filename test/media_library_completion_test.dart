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
import 'package:asmr_downloader/services/library/library_database_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakeMediaLibraryApi extends AsmrApi {
  _FakeMediaLibraryApi({required this.workInfoById});

  final Map<String, Map<String, dynamic>?> workInfoById;
  final List<String> workInfoCalls = [];
  final List<String> trackCalls = [];
  final List<String> coverCalls = [];

  @override
  Future<Map<String, dynamic>?> getWorkInfo(String id) async {
    workInfoCalls.add(id);
    return workInfoById[id];
  }

  @override
  Future<List<dynamic>?> getTracks(String id) async {
    trackCalls.add(id);
    return const [];
  }

  @override
  Future<Uint8List?> getCoverBytes(String url) async {
    coverCalls.add(url);
    return Uint8List.fromList([1, 2, 3]);
  }
}

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('media_library_completion_test');
  });

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('一键补全扫描作品的元数据、原版社团、tracks 和封面', () async {
    Directory(p.join(root.path, 'RJ12345678')).createSync(recursive: true);
    Directory(p.join(root.path, 'RJ87654321')).createSync(recursive: true);

    final libraryDatabase = LibraryDatabase.forTesting(NativeDatabase.memory());
    final cacheDatabase = CacheDatabase.forTesting(NativeDatabase.memory());
    final cache = CacheService(cacheDatabase);
    final api = _FakeMediaLibraryApi(
      workInfoById: {
        '12345678': {
          'source_id': 'RJ12345678',
          'title': '简体中文版作品',
          'circle': {'name': '中文翻译组'},
          'translation_info': {
            'is_original': false,
            'original_workno': 'RJ87654321',
          },
          'mainCoverUrl': 'https://example.com/translated.jpg',
        },
        '87654321': {
          'source_id': 'RJ87654321',
          'title': '日本語原版作品',
          'circle': {'name': '日文原版社团'},
          'translation_info': {'is_original': true},
          'mainCoverUrl': 'https://example.com/original.jpg',
        },
      },
    );
    addTearDown(libraryDatabase.close);
    addTearDown(cacheDatabase.close);

    final container = ProviderContainer(overrides: [
      libraryDatabaseProvider.overrideWithValue(libraryDatabase),
      cacheServiceProvider.overrideWithValue(cache),
      asmrApiProvider.overrideWithValue(api),
      rateLimiterProvider
          .overrideWith((ref) => RateLimiter(minInterval: Duration.zero)),
      mediaLibraryRootsProvider.overrideWith((ref) => [root.path]),
    ]);
    addTearDown(container.dispose);

    final progress = <MediaLibraryCompleteProgress>[];
    final result =
        await container.read(cacheCompleteServiceProvider).completeMediaLibrary(
              onProgress: progress.add,
              isCancelled: () => false,
            );

    expect(result.processed, 2);
    expect(result.total, 2);
    // 译作本身补了 workInfo；原版 workInfo 作为社团解析的一部分单独统计。
    expect(result.metadataFilled, 1);
    expect(result.originalCirclesFilled, 1);
    expect(result.tracksFilled, 2);
    expect(result.coversFilled, 2);
    expect(result.failed, 0);
    expect(result.skipped, 0);
    expect(api.workInfoCalls, ['12345678', '87654321']);
    expect(api.trackCalls, ['12345678', '87654321']);
    expect(api.coverCalls, [
      'https://example.com/translated.jpg',
      'https://example.com/original.jpg',
    ]);
    expect(await cache.getWorkInfo('RJ12345678'), isNotNull);
    expect(await cache.getWorkInfo('RJ87654321'), isNotNull);
    expect(progress.first.total, 2);
    expect(progress.last.processed, 2);
  });
}
