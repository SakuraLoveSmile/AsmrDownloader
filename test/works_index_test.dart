import 'dart:io';

import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory testBase;
  late WorksIndex index;

  WorkEntry entry(String sourceId, {bool dirExists = true, String? organizedAt}) {
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
    expect(got.sourceDir, p.join(testBase.path, 'dl', '社团-标题RJ00001', 'RJ00001'));

    final all = await index.list();
    expect(all.length, 2);

    await index.remove('RJ00001');
    expect(await index.get('RJ00001'), isNull);
    expect((await index.list()).length, 1);
  });

  test('upsert 同 sourceId 覆盖更新', () async {
    await index.upsert(entry('RJ00001'));
    await index.upsert(entry('RJ00001').copyWith(
        organizedAt: '2026-08-13T00:00:00.000'));

    final got = await index.get('RJ00001');
    expect(got!.organizedAt, '2026-08-13T00:00:00.000');
    expect((await index.list()).length, 1);
  });

  test('markOrganized 记录整理时间', () async {
    await index.upsert(entry('RJ00001'));
    await index.markOrganized('RJ00001',
        time: DateTime.parse('2026-08-13T01:02:03.000'));

    expect((await index.get('RJ00001'))!.organizedAt,
        '2026-08-13T01:02:03.000');
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
}
