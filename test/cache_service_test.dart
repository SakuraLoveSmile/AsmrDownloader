import 'dart:io';
import 'dart:typed_data';

import 'package:asmr_downloader/services/cache/cache_database.dart';
import 'package:asmr_downloader/services/cache/cache_service.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late CacheDatabase db;
  late CacheService service;

  setUp(() {
    db = CacheDatabase.forTesting(NativeDatabase.memory());
    service = CacheService(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('workInfo 增查改（upsert 覆盖）', () async {
    expect(await service.getWorkInfo('RJ01619789'), isNull);

    await service.saveWorkInfo('RJ01619789', {
      'title': '标题A',
      'circle': {'name': '社团'},
    });
    final data = await service.getWorkInfo('RJ01619789');
    expect(data?['title'], '标题A');
    expect(data?['circle']?['name'], '社团');

    // 同 key 覆盖更新
    await service.saveWorkInfo('RJ01619789', {'title': '标题B'});
    expect((await service.getWorkInfo('RJ01619789'))?['title'], '标题B');
    expect(await service.getCacheCount(), 1);
  });

  test('列表查询返回全部 workInfo 且按缓存时间倒序', () async {
    await db.into(db.workInfoEntries).insert(
          WorkInfoEntriesCompanion.insert(
            sourceId: 'RJ1',
            workInfoJson: '{}',
            cachedAt: drift.Value(DateTime(2026, 1, 1)),
          ),
        );
    await db.into(db.workInfoEntries).insert(
          WorkInfoEntriesCompanion.insert(
            sourceId: 'RJ2',
            workInfoJson: '{}',
            cachedAt: drift.Value(DateTime(2026, 2, 1)),
          ),
        );

    final entries = await service.listWorkInfoEntries();
    expect(entries.map((entry) => entry.sourceId), ['RJ2', 'RJ1']);
    expect(entries.map((entry) => entry.cachedAt), [
      DateTime(2026, 2, 1),
      DateTime(2026, 1, 1),
    ]);
  });

  test('列表查询只返回存在 tracks 或封面的 sourceId', () async {
    await service.saveWorkInfo('RJ1', {});
    await service.saveTracks('RJ1', []);
    await service.saveTracks('RJ2', []);
    await service.saveCover('RJ2', Uint8List.fromList([1]));
    await service.saveCover('RJ3', Uint8List.fromList([2]));

    expect(await service.listTracksSourceIds(), {'RJ1', 'RJ2'});
    expect(await service.listCoverSourceIds(), {'RJ2', 'RJ3'});
  });

  test('tracks 增查（List JSON 往返）', () async {
    await service.saveTracks('RJ01619789', [
      {
        'type': 'folder',
        'title': 'RJ01619789',
        'children': [
          {'type': 'audio', 'title': 'x.wav'},
        ],
      },
    ]);
    final tracks = await service.getTracks('RJ01619789');
    expect(tracks, hasLength(1));
    expect((tracks![0] as Map)['title'], 'RJ01619789');
    expect(await service.getTracks('不存在的'), isNull);
  });

  test('cover BLOB 读写', () async {
    expect(await service.hasCover('RJ1'), false);
    final bytes = Uint8List.fromList(List.generate(100, (i) => i));
    await service.saveCover('RJ1', bytes);
    expect(await service.hasCover('RJ1'), true);
    expect(await service.getCover('RJ1'), bytes);
  });

  test('计数与清空', () async {
    await service.saveWorkInfo('RJ1', {'a': 1});
    await service.saveWorkInfo('RJ2', {'a': 2});
    await service.saveTracks('RJ1', []);
    await service.saveCover('RJ1', Uint8List(1));

    expect(await service.getCacheCount(), 2);
    expect(await service.getTracksCount(), 1);
    expect(await service.getCoverCount(), 1);

    await service.clearCache();
    expect(await service.getCacheCount(), 0);
    expect(await service.getTracksCount(), 0);
    expect(await service.getCoverCount(), 0);
    expect(await service.getWorkInfo('RJ1'), isNull);
  });

  test('removeEntry 删除单个作品的全部缓存', () async {
    await service.saveWorkInfo('RJ1', {'a': 1});
    await service.saveWorkInfo('RJ2', {'a': 2});
    await service.saveTracks('RJ1', []);
    await service.saveCover('RJ1', Uint8List(1));

    await service.removeEntry('RJ1');
    expect(await service.getWorkInfo('RJ1'), isNull);
    expect(await service.getTracks('RJ1'), isNull);
    expect(await service.getCover('RJ1'), isNull);
    expect(await service.getWorkInfo('RJ2'), isNotNull);
  });

  test('findSourceIdByDigits 按数字段匹配已有缓存', () async {
    await service.saveWorkInfo('RJ01619789', {'a': 1});
    expect(await service.findSourceIdByDigits('1619789'), 'RJ01619789');
    expect(await service.findSourceIdByDigits('9999999'), isNull);
    expect(await service.findSourceIdByDigits(''), isNull);
  });

  group('导入导出（复制 .db 文件）', () {
    test('exportTo 生成完整文件，importFrom 后数据一致', () async {
      final base = Directory.systemTemp.createTempSync('cache_test');
      addTearDown(() => base.deleteSync(recursive: true));
      final mainDbPath = p.join(base.path, 'main.db');
      final exportPath = p.join(base.path, 'export.db');
      final importTarget = p.join(base.path, 'imported.db');

      // 导入导出针对 .db 文件，使用文件型缓存库（内存库无文件可复制）
      final fileDb = CacheDatabase.fromPath(mainDbPath);
      addTearDown(fileDb.close);
      final fileService = CacheService(fileDb);

      await fileService.saveWorkInfo('RJ01619789', {'title': '原标题'});
      await fileService.saveTracks('RJ01619789', [
        {'title': 'a.wav'}
      ]);
      await fileService.saveCover('RJ01619789', Uint8List.fromList([1, 2, 3]));

      await fileService.exportTo(exportPath);
      expect(File(exportPath).existsSync(), true);
      expect(File(exportPath).lengthSync(), greaterThan(0));

      // 独立实例从导出文件导入（覆盖目标路径）
      final service2 = CacheService(CacheDatabase.fromPath(importTarget));
      addTearDown(() => service2.database.close());
      await service2.importFrom(exportPath);

      final data = await service2.getWorkInfo('RJ01619789');
      expect(data?['title'], '原标题');
      expect(await service2.getTracks('RJ01619789'), hasLength(1));
      expect(
          await service2.getCover('RJ01619789'), Uint8List.fromList([1, 2, 3]));
      expect(File(importTarget).existsSync(), true);
    });

    test('importFrom 覆盖已有旧数据', () async {
      final base = Directory.systemTemp.createTempSync('cache_test2');
      addTearDown(() => base.deleteSync(recursive: true));
      final mainDbPath = p.join(base.path, 'main.db');
      final srcPath = p.join(base.path, 'src.db');

      final fileDb = CacheDatabase.fromPath(mainDbPath);
      addTearDown(fileDb.close);
      final fileService = CacheService(fileDb);

      // 目标库已有旧数据
      await fileService.saveWorkInfo('RJ111', {'title': '旧数据'});

      // 源库写入新数据后关闭
      final srcDb = CacheDatabase.fromPath(srcPath);
      await CacheService(srcDb).saveWorkInfo('RJ111', {'title': '新数据'});
      await srcDb.close();

      await fileService.importFrom(srcPath);
      expect((await fileService.getWorkInfo('RJ111'))?['title'], '新数据');
      // 导入后同一 service 实例可继续读写（连接已重建）
      await fileService.saveWorkInfo('RJ111', {'title': '导入后再写'});
      expect((await fileService.getWorkInfo('RJ111'))?['title'], '导入后再写');
    });
  });
}
