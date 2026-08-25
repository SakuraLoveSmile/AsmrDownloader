import 'dart:io';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/library/library_database.dart';
import 'package:asmr_downloader/services/library/library_database_providers.dart';
import 'package:asmr_downloader/services/library/media_library_service.dart';
import 'package:asmr_downloader/services/library/work_library_status.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory testBase;
  late Directory dlRoot;
  late Directory nasRoot;
  late LibraryDatabase database;
  late WorksIndex index;

  setUp(() {
    testBase = Directory.systemTemp.createTempSync('work_library_status_test');
    dlRoot = Directory(p.join(testBase.path, 'downloads'))..createSync();
    nasRoot = Directory(p.join(testBase.path, 'nas'))..createSync();
    database = LibraryDatabase.forTesting(NativeDatabase.memory());
    index = WorksIndex(
      filePath: p.join(testBase.path, 'works_index.json'),
      database: database,
    );
  });

  tearDown(() async {
    testBase.deleteSync(recursive: true);
    await database.close();
  });

  ProviderContainer makeContainer({
    String? sourceId,
    String? voiceWorkPath,
    List<String> roots = const [],
  }) {
    final container = ProviderContainer(overrides: [
      sourceIdProvider.overrideWith((ref) => sourceId),
      voiceWorkPathProvider.overrideWith((ref) => voiceWorkPath ?? dlRoot.path),
      downloadPathProvider.overrideWith((ref) => dlRoot.path),
      mediaLibraryRootsProvider.overrideWith((ref) => roots),
      libraryDatabaseProvider.overrideWithValue(database),
      worksIndexProvider.overrideWith((ref) => index),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('未搜索（sourceId 为空）时不产生状态', () async {
    final container = makeContainer(roots: [nasRoot.path]);
    expect(await container.read(workLibraryStatusProvider.future), isNull);
  });

  test('本机与媒体库均无记录时未入库', () async {
    final container = makeContainer(sourceId: 'RJ1000001');
    final status = await container.read(workLibraryStatusProvider.future);
    expect(status, isNotNull);
    expect(status!.inLibrary, isFalse);
    expect(status.localPaths, isEmpty);
    expect(status.externalLocations, isEmpty);
  });

  test('注册表条目且目录存在时识别为本机副本', () async {
    const sourceId = 'RJ1000002';
    final sourceDir = Directory(p.join(dlRoot.path, 'CV-标题', sourceId))
      ..createSync(recursive: true);
    await index.upsert(WorkEntry(
      sourceId: sourceId,
      dlPath: dlRoot.path,
      dirName: 'CV-标题',
      title: '标题',
      cvNames: 'CV',
    ));

    final container = makeContainer(sourceId: sourceId);
    final status = await container.read(workLibraryStatusProvider.future);
    expect(status!.inLibrary, isTrue);
    expect(status.localPaths, [sourceDir.path]);
    expect(status.externalLocations, isEmpty);
  });

  test('注册表目录被手动删除后不再视为本机副本', () async {
    const sourceId = 'RJ1000003';
    final sourceDir = Directory(p.join(dlRoot.path, 'CV-标题', sourceId))
      ..createSync(recursive: true);
    await index.upsert(WorkEntry(
      sourceId: sourceId,
      dlPath: dlRoot.path,
      dirName: 'CV-标题',
      title: '标题',
      cvNames: 'CV',
    ));

    final container = makeContainer(sourceId: sourceId);
    expect((await container.read(workLibraryStatusProvider.future))!.inLibrary,
        isTrue);

    sourceDir.deleteSync(recursive: true);
    container.invalidate(workLibraryStatusProvider);
    expect((await container.read(workLibraryStatusProvider.future))!.inLibrary,
        isFalse);
  });

  test('当前命名下的断点目录也算本机副本（无注册表）', () async {
    const sourceId = 'RJ1000004';
    final workDir = Directory(p.join(dlRoot.path, 'CV-标题', sourceId))
      ..createSync(recursive: true);

    final container = makeContainer(
      sourceId: sourceId,
      voiceWorkPath: p.join(dlRoot.path, 'CV-标题'),
    );
    final status = await container.read(workLibraryStatusProvider.future);
    expect(status!.localPaths, [workDir.path]);
  });

  test('NAS 扫描记录识别为外部副本，下载根目录内记录算本机', () async {
    const nasSourceId = 'RJ1000005';
    const localSourceId = 'RJ1000006';
    Directory(p.join(nasRoot.path, '社团', nasSourceId))
        .createSync(recursive: true);
    Directory(p.join(dlRoot.path, 'CV-标题', localSourceId))
        .createSync(recursive: true);

    // 扫描一次：两个容器共用同一个内存数据库，扫描结果互相可见
    final scanContainer = makeContainer(roots: [nasRoot.path, dlRoot.path]);
    await scanContainer.read(mediaLibraryServiceProvider).scanConfiguredRoots();

    // NAS 副本：voiceWorkPath 指向不存在目录，避免误判为本机
    final externalContainer = makeContainer(
      sourceId: nasSourceId,
      voiceWorkPath: p.join(dlRoot.path, '另一个标题'),
      roots: [nasRoot.path, dlRoot.path],
    );
    final external =
        await externalContainer.read(workLibraryStatusProvider.future);
    expect(external!.localPaths, isEmpty);
    expect(external.externalLocations.single.sourceId, nasSourceId);
    expect(external.inLibrary, isTrue);

    // 下载根目录内的扫描记录（手动拷入、无注册表）：算本机副本
    final localContainer = makeContainer(
      sourceId: localSourceId,
      voiceWorkPath: p.join(dlRoot.path, '另一个标题'),
      roots: [nasRoot.path, dlRoot.path],
    );
    final local = await localContainer.read(workLibraryStatusProvider.future);
    expect(local!.externalLocations, isEmpty);
    expect(local.localPaths.single, contains(localSourceId));
    expect(local.inLibrary, isTrue);
  });
}
