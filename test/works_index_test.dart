import 'dart:io';

import 'package:asmr_downloader/services/library/library_database.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory testBase;
  late WorksIndex index;

  WorkEntry entry(String sourceId,
      {bool dirExists = true, String? organizedAt}) {
    final dlPath = p.join(testBase.path, 'dl');
    final dirName = '社团-标题$sourceId';
    if (dirExists) {
      Directory(p.join(dlPath, dirName, sourceId)).createSync(recursive: true);
    }
    return WorkEntry(
      sourceId: sourceId,
      dlPath: dlPath,
      dirName: dirName,
      title: '标题$sourceId',
      cvNames: 'CV1&CV2',
      circleName: '社团',
      releaseDate: '2026-06-09',
      tags: ['舔耳', 'ASMR'],
      coverUrl: 'https://example.com/cover.jpg',
      organizedAt: organizedAt,
    );
  }

  setUp(() {
    testBase = Directory.systemTemp.createTempSync('works_index_test');
    index = WorksIndex(filePath: p.join(testBase.path, 'works_index.json'));
  });

  tearDown(() {
    testBase.deleteSync(recursive: true);
  });

  test('upsert/get/list/remove 往返', () async {
    expect(await index.list(), isEmpty);

    await index.upsert(entry('RJ00001'));
    await index.upsert(entry('RJ00002'));

    final got = await index.get('RJ00001');
    expect(got, isNotNull);
    expect(got!.title, '标题RJ00001');
    expect(got.cvNames, 'CV1&CV2');
    expect(got.circleName, '社团');
    expect(got.tags, ['舔耳', 'ASMR']);
    expect(
        got.sourceDir, p.join(testBase.path, 'dl', '社团-标题RJ00001', 'RJ00001'));

    final all = await index.list();
    expect(all.length, 2);

    await index.remove('RJ00001');
    expect(await index.get('RJ00001'), isNull);
    expect((await index.list()).length, 1);
  });

  test('upsert 同 sourceId 覆盖更新', () async {
    await index.upsert(entry('RJ00001'));
    await index.upsert(
        entry('RJ00001').copyWith(organizedAt: '2026-08-13T00:00:00.000'));

    final got = await index.get('RJ00001');
    expect(got!.organizedAt, '2026-08-13T00:00:00.000');
    expect((await index.list()).length, 1);
  });

  test('manuallyEditedAt 迁移后默认 null，updateMetadata 写入并保留往返', () async {
    await index.upsert(entry('RJ00001'));
    final before = await index.get('RJ00001');
    expect(before!.manuallyEditedAt, isNull);
    // 普通 upsert 不产生手动标记（与 updateMetadata 区分）
    expect(before.toJson()['manuallyEditedAt'], isNull);

    // 手动编辑：更新元数据并显式标记
    await index.updateMetadata(WorkEntry(
      sourceId: before.sourceId,
      dlPath: before.dlPath,
      dirName: before.dirName,
      title: '手动标题',
      cvNames: '手动CV1&手动CV2',
      circleName: '手动社团',
      releaseDate: '2026-01-01',
      tags: ['手动标签'],
      coverUrl: before.coverUrl,
      organizedAt: before.organizedAt,
    ));

    final edited = await index.get('RJ00001');
    expect(edited!.manuallyEditedAt, isNotNull);
    expect(edited.title, '手动标题');
    expect(edited.cvNames, '手动CV1&手动CV2');
    expect(edited.circleName, '手动社团');
    expect(edited.releaseDate, '2026-01-01');
    expect(edited.tags, ['手动标签']);

    // JSON 往返保留手动标记
    final restored = WorkEntry.fromJson(edited.toJson());
    expect(restored.manuallyEditedAt, isNotNull);
    expect(restored.title, '手动标题');
  });

  test('markOrganized 记录整理时间', () async {
    await index.upsert(entry('RJ00001'));
    await index.markOrganized('RJ00001',
        time: DateTime.parse('2026-08-13T01:02:03.000'));

    expect(
        (await index.get('RJ00001'))!.organizedAt, '2026-08-13T01:02:03.000');
  });

  test('listMissing / cleanMissing 清理目录不存在的条目', () async {
    await index.upsert(entry('RJ00001', dirExists: true));
    await index.upsert(entry('RJ00002', dirExists: false));
    await index.upsert(entry('RJ00003', dirExists: true));

    final missing = await index.listMissing();
    expect(missing.map((e) => e.sourceId), ['RJ00002']);

    final cleaned = await index.cleanMissing();
    expect(cleaned, 1);
    expect(await index.get('RJ00002'), isNull);
    expect((await index.list()).length, 2);
  });

  test('文件损坏时容错为空表', () async {
    File(index.filePath).writeAsStringSync('not json');
    expect(await index.list(), isEmpty);
  });

  test('sourceDirOverride：JSON 往返与 sourceDir 两分支', () {
    final flat = WorkEntry(
      sourceId: 'RJ00001',
      dlPath: p.join(testBase.path, 'dl'),
      dirName: 'RJ00001 - CV - 标题',
      title: '',
      cvNames: '',
      sourceDirOverride: p.join(testBase.path, 'dl', 'RJ00001 - CV - 标题'),
    );

    // JSON 往返保留 override
    final restored = WorkEntry.fromJson(flat.toJson());
    expect(restored.sourceDirOverride,
        p.join(testBase.path, 'dl', 'RJ00001 - CV - 标题'));

    // override 分支：sourceDir 直接指向显式目录，不拼接 {dlPath}/{dirName}/{sourceId}
    expect(
        restored.sourceDir, p.join(testBase.path, 'dl', 'RJ00001 - CV - 标题'));

    // 旧数据没有该字段 → 空串 → 标准结构重建
    final legacyJson = flat.toJson()..remove('sourceDirOverride');
    final legacy = WorkEntry.fromJson(legacyJson);
    expect(legacy.sourceDirOverride, '');
    expect(
      legacy.sourceDir,
      p.join(testBase.path, 'dl', 'RJ00001 - CV - 标题', 'RJ00001'),
    );

    // copyWith 保留 override
    final copied = flat.copyWith(organizedAt: '2026-08-13T00:00:00.000');
    expect(copied.sourceDirOverride,
        p.join(testBase.path, 'dl', 'RJ00001 - CV - 标题'));
  });

  test('schema v2 → v3 迁移：自动补充 sourceDirOverride 列，旧数据按空串读写', () async {
    final dbFile = File(p.join(testBase.path, 'v2.db'));

    // 以 v3 建表并写入旧数据（不含 override）
    final v3db = LibraryDatabase.fromPath(dbFile.path);
    await v3db.into(v3db.libraryWorks).insert(LibraryWorksCompanion.insert(
          sourceId: 'RJ00001',
          dlPath: Value(p.join(testBase.path, 'dl')),
          dirName: Value('社团-标题RJ00001'),
          title: Value('旧标题'),
          cvNames: Value('CV1'),
        ));
    await v3db.close();

    // 降级为 v2：删除新列并回退 user_version（模拟旧版本创建的数据库）。
    // 当前 user_version 仍为 3，重开不会触发迁移，可安全执行降级语句。
    final raw = LibraryDatabase.fromPath(dbFile.path);
    await raw.customStatement(
        'ALTER TABLE library_works DROP COLUMN source_dir_override');
    await raw.customStatement('PRAGMA user_version = 2');
    await raw.close();

    // v2 数据打开：迁移补列，旧数据 override 为空串、sourceDir 按标准结构重建
    final migratedDb = LibraryDatabase.fromPath(dbFile.path);
    addTearDown(migratedDb.close);
    final migratedIndex = WorksIndex(
      filePath: p.join(testBase.path, 'migrated.json'),
      database: migratedDb,
    );
    final legacy = await migratedIndex.get('RJ00001');
    expect(legacy, isNotNull);
    expect(legacy!.sourceDirOverride, '');
    expect(
      legacy.sourceDir,
      p.join(testBase.path, 'dl', '社团-标题RJ00001', 'RJ00001'),
    );

    // 迁移后写入 override 可读回（null ↔ '' 转换）
    await migratedIndex.upsert(legacy.copyWith(
        sourceDirOverride: p.join(testBase.path, 'flat', 'RJ00001 - CV - 标题')));
    final updated = await migratedIndex.get('RJ00001');
    expect(updated!.sourceDirOverride,
        p.join(testBase.path, 'flat', 'RJ00001 - CV - 标题'));
    expect(
        updated.sourceDir, p.join(testBase.path, 'flat', 'RJ00001 - CV - 标题'));

    // 空串写回 → 存 null → 读回仍为空串
    await migratedIndex.upsert(entry('RJ00001'));
    expect((await migratedIndex.get('RJ00001'))!.sourceDirOverride, '');
  });
}
