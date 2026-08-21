import 'dart:io';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/library/library_providers.dart';
import 'package:asmr_downloader/services/organize/navidrome_organizer.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory testBase;
  late Directory dlRoot;
  late Directory targetRoot;
  late WorksIndex index;

  setUp(() {
    testBase = Directory.systemTemp.createTempSync('works_library_test');
    dlRoot = Directory(p.join(testBase.path, 'downloads'))..createSync();
    targetRoot = Directory(p.join(testBase.path, 'navidrome'))..createSync();
    index = WorksIndex(filePath: p.join(testBase.path, 'works_index.json'));
  });

  tearDown(() {
    testBase.deleteSync(recursive: true);
  });

  test('作品库和未整理徽标会识别已删除的整理文件', () async {
    const sourceId = 'RJ700001';
    final sourceDir = Directory(p.join(dlRoot.path, 'CV-标题', sourceId))
      ..createSync(recursive: true);
    File(p.join(sourceDir.path, '音声.wav')).writeAsStringSync('source');

    final entry = WorkEntry(
      sourceId: sourceId,
      dlPath: dlRoot.path,
      dirName: 'CV-标题',
      title: '标题',
      cvNames: 'CV',
      circleName: '社团',
      organizedAt: '2026-08-21T00:00:00.000',
    );
    await index.upsert(entry);

    final targetDir = Directory(
      NavidromeOrganizer.targetDirPath(
        targetRoot: targetRoot.path,
        circleName: entry.circleName,
        sourceId: entry.sourceId,
        cvNames: entry.cvNames,
        title: entry.title,
      ),
    )..createSync(recursive: true);
    final targetFile = File(p.join(targetDir.path, '音声.wav'))
      ..writeAsStringSync('organized');

    final container = ProviderContainer(overrides: [
      downloadPathProvider.overrideWith((ref) => dlRoot.path),
      navidromePathProvider.overrideWith((ref) => targetRoot.path),
      worksIndexProvider.overrideWith((ref) => index),
    ]);
    addTearDown(container.dispose);

    final organizedItems =
        await container.read(worksLibraryServiceProvider).listWorks();
    expect(organizedItems.single.organized, true);
    expect(await container.read(unorganizedCountProvider.future), 0);

    targetFile.deleteSync();
    final missingItems =
        await container.read(worksLibraryServiceProvider).listWorks();
    expect(missingItems.single.organized, false);

    container.invalidate(unorganizedCountProvider);
    expect(await container.read(unorganizedCountProvider.future), 1);
  });
}
