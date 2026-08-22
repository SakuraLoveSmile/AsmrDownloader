import 'dart:convert';
import 'dart:io';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/cache/cache_database.dart';
import 'package:asmr_downloader/services/cache/cache_library_providers.dart';
import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:asmr_downloader/services/cache/cache_service.dart';
import 'package:asmr_downloader/services/library/library_database.dart';
import 'package:asmr_downloader/services/library/library_database_providers.dart';
import 'package:asmr_downloader/services/library/media_library_scanner.dart';
import 'package:asmr_downloader/services/library/media_library_service.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('media_library_test');
  });

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('轻量扫描只识别目录名中的 RJ 号，不读取文件名', () async {
    Directory(p.join(root.path, '社团-作品', 'RJ12345678'))
        .createSync(recursive: true);
    Directory(p.join(root.path, '备用', '深层', 'RJ87654321'))
        .createSync(recursive: true);
    File(p.join(root.path, 'RJ99999999.mp3')).writeAsStringSync('not a dir');
    Directory(p.join(root.path, '2026')).createSync();

    final hits = await scanMediaLibraryRoot(rootPath: root.path);

    expect(hits.map((hit) => hit.sourceId), ['RJ12345678', 'RJ87654321']);
    expect(
        hits.every((hit) => Directory(hit.matchedPath).existsSync()), isTrue);
  });

  test('扫描结果持久化，NAS 暂时不可用时保留上次 RJ 记录', () async {
    final workDir = Directory(p.join(root.path, 'RJ12345678'))
      ..createSync(recursive: true);
    final database = LibraryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final container = ProviderContainer(overrides: [
      libraryDatabaseProvider.overrideWithValue(database),
      mediaLibraryRootsProvider.overrideWith((ref) => [root.path]),
    ]);
    addTearDown(container.dispose);

    final service = container.read(mediaLibraryServiceProvider);
    final first = await service.scanConfiguredRoots();
    expect(first.workCount, 1);
    expect((await service.listLocations()).single.matchedPath, workDir.path);
    expect(
      (await service.findExistingOutsideRoot(
              sourceId: 'RJ12345678', excludedRoot: '/tmp/local-downloads'))
          ?.matchedPath,
      workDir.path,
    );

    root.deleteSync(recursive: true);
    final second = await service.scanConfiguredRoots();
    expect(second.unavailableRoots, [root.path]);
    expect((await service.listLocations()).single.sourceId, 'RJ12345678');
  });

  test('媒体库按 sourceId 关联缓存数据库中的作品元数据', () async {
    Directory(p.join(root.path, 'RJ12345678')).createSync(recursive: true);
    final libraryDatabase = LibraryDatabase.forTesting(NativeDatabase.memory());
    final cacheDatabase =
        CacheService(CacheDatabase.forTesting(NativeDatabase.memory()));
    addTearDown(libraryDatabase.close);
    addTearDown(cacheDatabase.database.close);
    await cacheDatabase.saveWorkInfo('RJ12345678', {
      'title': '缓存标题',
      'circle': {'name': '测试社团'},
    });

    final container = ProviderContainer(overrides: [
      libraryDatabaseProvider.overrideWithValue(libraryDatabase),
      cacheServiceProvider.overrideWithValue(cacheDatabase),
      mediaLibraryRootsProvider.overrideWith((ref) => [root.path]),
    ]);
    addTearDown(container.dispose);

    final library = await container.read(cachedLibraryProvider.future);

    expect(library.entries, hasLength(1));
    expect(library.entries.single.sourceId, 'RJ12345678');
    expect(library.entries.single.title, '缓存标题');
    expect(library.entries.single.locations.single.matchedPath,
        p.join(root.path, 'RJ12345678'));
  });

  test('媒体库可用作品索引数据库补齐社团和 CV 分类信息', () async {
    Directory(p.join(root.path, 'RJ12345678')).createSync(recursive: true);
    final libraryDatabase = LibraryDatabase.forTesting(NativeDatabase.memory());
    final cacheDatabase =
        CacheService(CacheDatabase.forTesting(NativeDatabase.memory()));
    addTearDown(libraryDatabase.close);
    addTearDown(cacheDatabase.database.close);
    await libraryDatabase.into(libraryDatabase.libraryWorks).insert(
          LibraryWorksCompanion.insert(
            sourceId: 'RJ12345678',
            title: const Value('数据库标题'),
            circleName: const Value('数据库社团'),
            cvNames: const Value('数据库 CV'),
          ),
        );

    final container = ProviderContainer(overrides: [
      libraryDatabaseProvider.overrideWithValue(libraryDatabase),
      cacheServiceProvider.overrideWithValue(cacheDatabase),
      mediaLibraryRootsProvider.overrideWith((ref) => [root.path]),
    ]);
    addTearDown(container.dispose);

    final library = await container.read(cachedLibraryProvider.future);

    expect(library.entries.single.title, '数据库标题');
    expect(library.entries.single.circleName, '数据库社团');
    expect(library.entries.single.cvNames, ['数据库 CV']);
  });

  test('WorksIndex 首次访问自动迁移旧 JSON', () async {
    final legacyPath = p.join(root.path, 'works_index.json');
    File(legacyPath).writeAsStringSync(jsonEncode({
      'RJ12345678': WorkEntry(
        sourceId: 'RJ12345678',
        dlPath: root.path,
        dirName: '旧目录',
        title: '旧标题',
        cvNames: 'CV',
      ).toJson(),
    }));

    final index = WorksIndex(filePath: legacyPath);
    addTearDown(index.close);
    final entry = await index.get('RJ12345678');

    expect(entry, isNotNull);
    expect(entry!.title, '旧标题');
    expect(entry.sourceDir, p.join(root.path, '旧目录', 'RJ12345678'));
  });
}
