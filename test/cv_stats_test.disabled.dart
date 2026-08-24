import 'dart:io';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/cache/cache_database.dart';
import 'package:asmr_downloader/services/cache/cache_library_providers.dart';
import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:asmr_downloader/services/cache/cache_service.dart';
import 'package:asmr_downloader/services/library/cv_stats_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

CachedLibraryEntry _entry(String sourceId, List<String> cvs) {
  return CachedLibraryEntry(
    sourceId: sourceId,
    cachedAt: DateTime(2026, 1, 1),
    workInfo: {
      'vas': cvs.map((c) => {'name': c}).toList(),
    },
    hasTracks: false,
    hasCover: false,
  );
}

void main() {
  group('cvStatsProvider 聚合', () {
    late CacheDatabase db;
    late CacheService service;

    setUp(() {
      db = CacheDatabase.forTesting(NativeDatabase.memory());
      service = CacheService(db);
    });
    tearDown(() => db.close());

    test('多 CV 作品分别计入各 CV；同作品内重复 CV 名只计一次；无 CV 不入统计',
        () async {
      final container = ProviderContainer(overrides: [
        cacheServiceProvider.overrideWithValue(service),
        cachedLibraryProvider.overrideWith((ref) async => const CachedLibrary([])),
      ]);
      addTearDown(container.dispose);

      // 预置歌曲数（audio 节点数）
      await service.saveTracks('RJ1', [
        {'type': 'audio'},
        {'type': 'audio'},
        {'type': 'audio'},
      ]);
      await service.saveTracks('RJ2', List.filled(5, {'type': 'audio'}));
      await service.saveTracks('RJ3', [
        {'type': 'audio'},
        {'type': 'audio'},
      ]);
      await service.saveTracks('RJ4', List.filled(7, {'type': 'audio'}));

      final library = CachedLibrary([
        _entry('RJ1', ['Alice', 'Bob']),
        _entry('RJ2', ['Alice', 'Bob']),
        // 同作品内重复 CV 名只计一次，albumCount +1、trackCount +2
        _entry('RJ3', ['Alice', 'Alice']),
        // 无 CV 名，不计入统计
        _entry('RJ4', []),
      ]);

      // override 数量需保持不变（先放占位再改值，合法）
      container.updateOverrides([
        cacheServiceProvider.overrideWithValue(service),
        cachedLibraryProvider.overrideWith((ref) async => library),
      ]);

      final stats = await container.read(cvStatsProvider.future);

      // Alice: 3 张专辑、10 首；Bob: 2 张专辑、8 首；按专辑数降序 Alice 在前
      expect(stats.map((s) => s.name), ['Alice', 'Bob']);
      final alice = stats.firstWhere((s) => s.name == 'Alice');
      expect(alice.albumCount, 3);
      expect(alice.trackCount, 10);
      final bob = stats.firstWhere((s) => s.name == 'Bob');
      expect(bob.albumCount, 2);
      expect(bob.trackCount, 8);
      // 无 CV 的作品不入统计
      expect(stats.length, 2);
    });

    test('排序：专辑数降序 → 歌曲数降序 → 名称小写', () async {
      final container = ProviderContainer(overrides: [
        cacheServiceProvider.overrideWithValue(service),
        cachedLibraryProvider.overrideWith((ref) async => const CachedLibrary([])),
      ]);
      addTearDown(container.dispose);

      await service.saveTracks('RJ1', List.filled(2, {'type': 'audio'}));
      await service.saveTracks('RJ2', List.filled(4, {'type': 'audio'}));
      await service.saveTracks('RJ3', List.filled(2, {'type': 'audio'}));
      final library = CachedLibrary([
        _entry('RJ1', ['Zeta']), // 1 专辑 2 曲
        _entry('RJ2', ['Yan']), // 1 专辑 4 曲 → 歌曲数最多
        _entry('RJ3', ['Alpha']), // 1 专辑 2 曲，与 Zeta 同曲数，名称靠前
      ]);
      container.updateOverrides([
        cacheServiceProvider.overrideWithValue(service),
        cachedLibraryProvider.overrideWith((ref) async => library),
      ]);
      final stats = await container.read(cvStatsProvider.future);
      expect(stats.map((s) => s.name), ['Yan', 'Alpha', 'Zeta']);
    });
  });

  group('getAudioTrackCounts 递归计数', () {
    late CacheDatabase db;
    late CacheService service;

    setUp(() {
      db = CacheDatabase.forTesting(NativeDatabase.memory());
      service = CacheService(db);
    });
    tearDown(() => db.close());

    test('嵌套 folder 递归计数；text/image 节点不计', () async {
      final tree = [
        {'type': 'audio', 'title': 'a1'},
        {
          'type': 'folder',
          'title': 'f1',
          'children': [
            {'type': 'audio', 'title': 'a2'},
            {'type': 'image', 'title': 'i1'},
            {
              'type': 'folder',
              'title': 'f2',
              'children': [
                {'type': 'audio', 'title': 'a3'},
                {'type': 'text', 'title': 't1'},
              ]
            },
          ]
        },
        {'type': 'text', 'title': 't2'},
      ];
      await service.saveTracks('RJX', tree);
      final counts = await service.getAudioTrackCounts();
      expect(counts['RJX'], 3);
    });
  });

  group('cvAvatarIndexProvider 头像索引', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cv_avatar_');
    });
    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<Map<String, String>> buildIndex(String dir) async {
      final container = ProviderContainer(overrides: [
        cvAvatarPathProvider.overrideWith((ref) => dir),
      ]);
      addTearDown(container.dispose);
      return await container.read(cvAvatarIndexProvider.future);
    }

    test('扩展名过滤', () async {
      await File(p.join(tempDir.path, 'alice.png')).writeAsBytes([1]);
      await File(p.join(tempDir.path, 'bob.jpg')).writeAsBytes([1]);
      await File(p.join(tempDir.path, 'CLARA.PNG')).writeAsBytes([1]);
      await File(p.join(tempDir.path, 'dan.gif')).writeAsBytes([1]);
      await File(p.join(tempDir.path, 'note.txt')).writeAsBytes([1]);
      await File(p.join(tempDir.path, 'ignore.md')).writeAsBytes([1]);

      final index = await buildIndex(tempDir.path);
      expect(index.containsKey('alice'), isTrue);
      expect(index.containsKey('bob'), isTrue);
      expect(index.containsKey('CLARA'), isTrue); // 大写扩展名归一
      expect(index.containsKey('dan'), isTrue);
      expect(index.containsKey('note'), isFalse); // 非图片被过滤
      expect(index.containsKey('ignore'), isFalse);
    });

    test('精确名优先 + 小写 fallback', () async {
      await File(p.join(tempDir.path, 'Alice.png')).writeAsBytes([1]);
      await File(p.join(tempDir.path, 'alice.jpg')).writeAsBytes([1]);

      final index = await buildIndex(tempDir.path);
      // 精确 "Alice" 命中 Alice.png（精确优先于同名小写文件）
      final exact = findCvAvatarPath(index, 'Alice');
      expect(exact, p.join(tempDir.path, 'Alice.png'));
      // 小写 "alice" 命中 alice.jpg
      final lower = findCvAvatarPath(index, 'alice');
      expect(lower, p.join(tempDir.path, 'alice.jpg'));
      // 仅大小写不同的查询也能 fallback 命中
      expect(findCvAvatarPath(index, 'ALICE'), isNotNull);
    });
  });

  group('setCvAvatar / clearCvAvatar', () {
    late Directory tempDir;
    late Directory srcDir;
    late ProviderContainer container;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cv_avatar_w_');
      srcDir = await Directory.systemTemp.createTemp('cv_src_');
      container = ProviderContainer(overrides: [
        cvAvatarPathProvider.overrideWith((ref) => tempDir.path),
      ]);
    });
    tearDown(() async {
      container.dispose();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
      if (await srcDir.exists()) await srcDir.delete(recursive: true);
    });

    test('sanitize：含 / : 等字符的 CV 名能落盘且可被索引命中', () async {
      final src = File(p.join(srcDir.path, 'source.png'));
      await src.writeAsBytes([1, 2, 3]);

      await container.read(setCvAvatarProvider((
        dir: tempDir.path,
        cvName: 'A/B:C',
        sourceFile: src.path,
      )).future);

      // 文件名被 sanitize 为 A_B_C.png 并落盘
      final dest = File(p.join(tempDir.path, 'A_B_C.png'));
      expect(await dest.exists(), isTrue);

      // 索引刷新后能命中（按原始 CV 名查询，经 sanitize）
      container.invalidate(cvAvatarIndexProvider);
      final index = await container.read(cvAvatarIndexProvider.future);
      expect(findCvAvatarPath(index, 'A/B:C'), dest.path);

      // 覆盖同名旧文件：再设一次，目标文件不变且内容更新
      final src2 = File(p.join(srcDir.path, 'source2.png'));
      await src2.writeAsBytes([9, 9, 9]);
      await container.read(setCvAvatarProvider((
        dir: tempDir.path,
        cvName: 'A/B:C',
        sourceFile: src2.path,
      )).future);
      expect(await dest.readAsBytes(), [9, 9, 9]);
    });

    test('clearCvAvatar 删除正确文件', () async {
      final src = File(p.join(srcDir.path, 'source.png'));
      await src.writeAsBytes([1]);
      await container.read(setCvAvatarProvider((
        dir: tempDir.path,
        cvName: 'Alice',
        sourceFile: src.path,
      )).future);

      final dest = File(p.join(tempDir.path, 'Alice.png'));
      expect(await dest.exists(), isTrue);

      await container.read(clearCvAvatarProvider((
        dir: tempDir.path,
        cvName: 'Alice',
      )).future);
      expect(await dest.exists(), isFalse);

      container.invalidate(cvAvatarIndexProvider);
      final index = await container.read(cvAvatarIndexProvider.future);
      expect(findCvAvatarPath(index, 'Alice'), isNull);
    });
  });
}
