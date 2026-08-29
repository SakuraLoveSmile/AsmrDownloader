import 'dart:io';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/library/library_providers.dart';
import 'package:asmr_downloader/services/library/works_library_service.dart';
import 'package:asmr_downloader/services/organize/navidrome_organizer.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 测试用注册表：统计 upsert 调用次数（判断路径自愈是否写回），
/// 并可模拟 [list] 时目录已被并发删除（扫描与合并之间目录失效）。
class _TestWorksIndex extends WorksIndex {
  _TestWorksIndex(String filePath, {this.dirToDeleteOnList})
      : super(filePath: filePath);

  final String? dirToDeleteOnList;
  int upsertCount = 0;

  @override
  Future<void> upsert(WorkEntry entry) async {
    upsertCount++;
    await super.upsert(entry);
  }

  @override
  Future<List<WorkEntry>> list() async {
    final entries = await super.list();
    final dir = dirToDeleteOnList;
    if (dir != null) {
      Directory(dir).deleteSync(recursive: true);
    }
    return entries;
  }
}

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

  ProviderContainer makeContainer({WorksIndex? indexOverride}) {
    final container = ProviderContainer(overrides: [
      downloadPathProvider.overrideWith((ref) => dlRoot.path),
      navidromePathProvider.overrideWith((ref) => targetRoot.path),
      worksIndexProvider.overrideWith((ref) => indexOverride ?? index),
    ]);
    addTearDown(container.dispose);
    return container;
  }

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

  test('删除本机下载只删除临时目录，保留索引和 NAS 整理内容', () async {
    const sourceId = 'RJ700002';
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
    );
    await index.upsert(entry);

    final organizedDir = Directory(
      NavidromeOrganizer.targetDirPath(
        targetRoot: targetRoot.path,
        circleName: entry.circleName,
        sourceId: entry.sourceId,
        cvNames: entry.cvNames,
        title: entry.title,
      ),
    )..createSync(recursive: true);
    final organizedFile = File(p.join(organizedDir.path, '音声.wav'))
      ..writeAsStringSync('organized');

    final container = ProviderContainer(overrides: [
      downloadPathProvider.overrideWith((ref) => dlRoot.path),
      navidromePathProvider.overrideWith((ref) => targetRoot.path),
      worksIndexProvider.overrideWith((ref) => index),
    ]);
    addTearDown(container.dispose);

    final item =
        (await container.read(worksLibraryServiceProvider).listWorks()).single;
    await container.read(worksLibraryServiceProvider).deleteLocalWork(item);

    expect(sourceDir.existsSync(), isFalse);
    expect(organizedFile.readAsStringSync(), 'organized');
    expect(await index.get(sourceId), isNotNull);
  });

  test('删除本机下载拒绝下载根目录、整理目标和根目录之外的路径', () async {
    final externalDir = Directory(p.join(testBase.path, 'external'))
      ..createSync(recursive: true);
    final nestedTarget = Directory(p.join(dlRoot.path, 'organized'))
      ..createSync(recursive: true);
    final localDir = Directory(p.join(dlRoot.path, 'CV-标题', 'RJ700003'))
      ..createSync(recursive: true);

    final container = ProviderContainer(overrides: [
      downloadPathProvider.overrideWith((ref) => dlRoot.path),
      navidromePathProvider.overrideWith((ref) => nestedTarget.path),
    ]);
    addTearDown(container.dispose);
    final service = container.read(worksLibraryServiceProvider);

    WorksListItem itemFor(String sourceDir) => WorksListItem(
          sourceId: 'RJ700003',
          title: '标题',
          cvNames: 'CV',
          circleName: '社团',
          dirName: 'CV-标题',
          dlPath: dlRoot.path,
          sourceDir: sourceDir,
          sourceDirOverride: '',
          organizedAt: null,
          verifyNote: null,
          verifyRepairable: false,
          trackCount: 0,
          missingSubtitleCount: 0,
          convertibleVttCount: 0,
        );

    await expectLater(
      service.deleteLocalWork(itemFor(dlRoot.path)),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      service.deleteLocalWork(itemFor(nestedTarget.path)),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      service.deleteLocalWork(itemFor(externalDir.path)),
      throwsA(isA<StateError>()),
    );

    expect(Directory(dlRoot.path).existsSync(), isTrue);
    expect(nestedTarget.existsSync(), isTrue);
    expect(externalDir.existsSync(), isTrue);
    expect(localDir.existsSync(), isTrue);
  });

  test('扁平作品（RJ号 - CV - 标题/）：音轨数与三段式目录名解析正确', () async {
    // 扁平结构：<dlRoot>/RJ111111 - CV - 标题/audio.wav（无内层 RJ 目录）
    final flatDir = Directory(p.join(dlRoot.path, 'RJ111111 - CV1&CV2 - 扁平标题'))
      ..createSync(recursive: true);
    File(p.join(flatDir.path, 'e01_舔耳.wav')).writeAsStringSync('a');
    File(p.join(flatDir.path, 'e02_口笛.wav')).writeAsStringSync('b');

    final container = ProviderContainer(overrides: [
      downloadPathProvider.overrideWith((ref) => dlRoot.path),
      navidromePathProvider.overrideWith((ref) => targetRoot.path),
      worksIndexProvider.overrideWith((ref) => index),
    ]);
    addTearDown(container.dispose);

    final items = await container.read(worksLibraryServiceProvider).listWorks();
    expect(items, hasLength(1));
    final item = items.single;
    expect(item.sourceId, 'RJ111111');
    // sourceDirOverride 指向真实作品目录（不再多拼一层 RJ 目录）
    expect(item.sourceDirOverride, flatDir.path);
    expect(item.sourceDir, flatDir.path);
    // 音轨数正常（修复前为 0）
    expect(item.trackCount, 2);
    // 三段式目录名解析：CV / 标题
    expect(item.title, '扁平标题');
    expect(item.cvNames, 'CV1&CV2');
  });

  test('circle 下的扁平作品同样识别（dirName 保留三段式名称）', () async {
    final flatDir =
        Directory(p.join(dlRoot.path, '社团X', 'RJ222222 - CV_A - 标题2'))
          ..createSync(recursive: true);
    File(p.join(flatDir.path, 'e01.a.wav')).writeAsStringSync('a');

    final container = ProviderContainer(overrides: [
      downloadPathProvider.overrideWith((ref) => dlRoot.path),
      navidromePathProvider.overrideWith((ref) => targetRoot.path),
      worksIndexProvider.overrideWith((ref) => index),
    ]);
    addTearDown(container.dispose);

    final items = await container.read(worksLibraryServiceProvider).listWorks();
    expect(items, hasLength(1));
    final item = items.single;
    expect(item.sourceId, 'RJ222222');
    expect(item.sourceDir, flatDir.path);
    expect(item.dlPath, p.join(dlRoot.path, '社团X'));
    expect(item.dirName, 'RJ222222 - CV_A - 标题2');
    expect(item.title, '标题2');
    expect(item.cvNames, 'CV_A');
    expect(item.trackCount, 1);
  });

  // ---------- 扫描基线（空注册表）：确认现有扫描器本身没问题 ----------

  test('扫描基线：外层包装 + 内层 RJ 识别为真实音轨目录', () async {
    final wrapper = Directory(p.join(dlRoot.path, 'RJ12345678 - CV - 标题'))
      ..createSync();
    final inner = Directory(p.join(wrapper.path, 'RJ12345678'))..createSync();
    File(p.join(inner.path, '01.wav')).writeAsStringSync('a');
    File(p.join(inner.path, '02.wav')).writeAsStringSync('b');

    final items =
        await makeContainer().read(worksLibraryServiceProvider).listWorks();
    expect(items, hasLength(1));
    expect(items.single.sourceId, 'RJ12345678');
    expect(items.single.trackCount, 2);
    expect(items.single.sourceDir, inner.path);
  });

  test('扫描基线：扁平目录识别为当前作品目录', () async {
    final flat = Directory(p.join(dlRoot.path, 'RJ12345678 - CV - 标题'))
      ..createSync();
    File(p.join(flat.path, '01.wav')).writeAsStringSync('a');
    File(p.join(flat.path, '02.wav')).writeAsStringSync('b');

    final items =
        await makeContainer().read(worksLibraryServiceProvider).listWorks();
    expect(items, hasLength(1));
    final item = items.single;
    expect(item.trackCount, 2);
    expect(item.sourceDir, flat.path);
  });

  test('扫描基线：社团三层目录识别为真实音轨目录', () async {
    final wrapper = Directory(p.join(dlRoot.path, '社团', 'RJ12345678 - CV - 标题'))
      ..createSync(recursive: true);
    final inner = Directory(p.join(wrapper.path, 'RJ12345678'))..createSync();
    File(p.join(inner.path, '01.wav')).writeAsStringSync('a');
    File(p.join(inner.path, '02.wav')).writeAsStringSync('b');

    final items =
        await makeContainer().read(worksLibraryServiceProvider).listWorks();
    expect(items, hasLength(1));
    final item = items.single;
    expect(item.trackCount, 2);
    expect(item.sourceDir, inner.path);
  });

  // ---------- 注册表旧路径遮蔽自愈回归 ----------

  test('注册表旧路径失效时使用扫描到的新路径并自动修复注册表', () async {
    const sourceId = 'RJ12345678';
    // 旧路径 <testBase>/old_downloads/RJ12345678 已不存在
    final stale = WorkEntry(
      sourceId: sourceId,
      dlPath: p.join(testBase.path, 'old_downloads'),
      dirName: 'RJ12345678',
      title: '手动标题',
      cvNames: 'CV手动',
      circleName: '手动社团',
      releaseDate: '2026-08-01',
      tags: const ['放松', '治愈'],
      coverUrl: 'https://example.com/cover.jpg',
      manuallyEditedAt: DateTime(2026, 8, 1),
    );
    await index.upsert(stale);
    expect(Directory(stale.sourceDir).existsSync(), isFalse);

    // 磁盘真实目录：<dlRoot>/社团/RJ12345678 - CV - 标题/
    final newDir = Directory(
      p.join(dlRoot.path, '社团', 'RJ12345678 - CV - 标题'),
    )..createSync(recursive: true);
    File(p.join(newDir.path, '01.wav')).writeAsStringSync('a');
    File(p.join(newDir.path, '02.wav')).writeAsStringSync('b');

    final items =
        await makeContainer().read(worksLibraryServiceProvider).listWorks();
    expect(items, hasLength(1));
    final item = items.single;
    // 立即用真实目录统计音轨，sourceDir 指向新目录
    expect(item.trackCount, 2);
    expect(item.sourceDir, newDir.path);
    expect(item.sourceDirOverride, newDir.path);
    expect(item.dlPath, p.join(dlRoot.path, '社团'));
    expect(item.dirName, 'RJ12345678 - CV - 标题');
    // 手动编辑元数据保留
    expect(item.title, '手动标题');
    expect(item.cvNames, 'CV手动');
    expect(item.circleName, '手动社团');

    // 注册表目录字段已自愈；手动元数据不被覆盖
    final healed = await index.get(sourceId);
    expect(healed, isNotNull);
    expect(healed!.sourceDir, newDir.path);
    expect(healed.dlPath, p.join(dlRoot.path, '社团'));
    expect(healed.dirName, 'RJ12345678 - CV - 标题');
    expect(healed.sourceDirOverride, newDir.path);
    expect(healed.manuallyEditedAt, DateTime(2026, 8, 1));
    expect(healed.title, '手动标题');
    expect(healed.cvNames, 'CV手动');
    expect(healed.circleName, '手动社团');
    expect(healed.releaseDate, '2026-08-01');
    expect(healed.tags, ['放松', '治愈']);
    expect(healed.coverUrl, 'https://example.com/cover.jpg');
  });

  test('注册表有效路径保持优先，不被扫描到的另一同 sourceId 路径覆盖', () async {
    const sourceId = 'RJ12345678';
    final registryDir = Directory(p.join(dlRoot.path, 'CV-标题', sourceId))
      ..createSync(recursive: true);
    File(p.join(registryDir.path, '01.wav')).writeAsStringSync('a');
    await index.upsert(WorkEntry(
      sourceId: sourceId,
      dlPath: dlRoot.path,
      dirName: 'CV-标题',
      title: '原标题',
      cvNames: '',
    ));

    // 扫描器同时发现的另一份同 sourceId 目录（扁平复制）
    final otherDir = Directory(
      p.join(dlRoot.path, '社团', 'RJ12345678 - CV - 标题'),
    )..createSync(recursive: true);
    File(p.join(otherDir.path, 'e01.wav')).writeAsStringSync('b');
    File(p.join(otherDir.path, 'e02.wav')).writeAsStringSync('c');

    final items =
        await makeContainer().read(worksLibraryServiceProvider).listWorks();
    expect(items, hasLength(1));
    final item = items.single;
    // 继续使用注册表路径，音轨只统计注册表目录
    expect(item.sourceDir, registryDir.path);
    expect(item.dirName, 'CV-标题');
    expect(item.sourceDirOverride, isEmpty);
    expect(item.trackCount, 1);

    // 未发生路径自愈，注册表不被覆盖
    final kept = await index.get(sourceId);
    expect(kept!.dlPath, dlRoot.path);
    expect(kept.dirName, 'CV-标题');
    expect(kept.sourceDirOverride, isEmpty);
    expect(kept.title, '原标题');
  });

  test('扫描目录在合并前失效时禁止修复注册表（trackCount=0 且无写回）', () async {
    const sourceId = 'RJ12345678';
    final stale = WorkEntry(
      sourceId: sourceId,
      dlPath: p.join(testBase.path, 'old_downloads'),
      dirName: 'RJ12345678',
      title: '手动标题',
      cvNames: '',
      manuallyEditedAt: DateTime(2026, 8, 1),
    );
    await index.upsert(stale);
    expect(Directory(stale.sourceDir).existsSync(), isFalse);

    // 新目录在扫描时真实存在，但合并前被并发删除：discovered 目录也失效
    final newDir = Directory(
      p.join(dlRoot.path, '社团', 'RJ12345678 - CV - 标题'),
    )..createSync(recursive: true);
    File(p.join(newDir.path, '01.wav')).writeAsStringSync('a');

    final testIndex =
        _TestWorksIndex(index.filePath, dirToDeleteOnList: newDir.path);
    final items = await makeContainer(indexOverride: testIndex)
        .read(worksLibraryServiceProvider)
        .listWorks();

    // 注册表与扫描路径都失效：条目保留注册表路径，音轨无法统计
    expect(items, hasLength(1));
    expect(items.single.sourceDir, stale.sourceDir);
    expect(items.single.trackCount, 0);
    // 不执行 upsert，注册表保持原值
    expect(testIndex.upsertCount, 0);
    final kept = await index.get(sourceId);
    expect(kept!.sourceDir, stale.sourceDir);
    expect(kept.manuallyEditedAt, DateTime(2026, 8, 1));
    expect(kept.title, '手动标题');
  });

  test('下载根目录不可访问时不执行注册表路径写回', () async {
    const sourceId = 'RJ12345678';
    const staleId = 'RJ99999999';
    // 注册表条目 A：目录真实存在（根不可访问时仍列出）
    final realDir = Directory(p.join(dlRoot.path, 'CV-标题', sourceId))
      ..createSync(recursive: true);
    File(p.join(realDir.path, '01.wav')).writeAsStringSync('a');
    await index.upsert(WorkEntry(
      sourceId: sourceId,
      dlPath: dlRoot.path,
      dirName: 'CV-标题',
      title: '标题A',
      cvNames: '',
    ));
    // 注册表条目 B：目录已失效 —— 不得因扫描为空而改写/删除
    await index.upsert(WorkEntry(
      sourceId: staleId,
      dlPath: dlRoot.path,
      dirName: '旧目录',
      title: '标题B',
      cvNames: '',
    ));

    final missingRoot = Directory(p.join(testBase.path, 'missing_downloads'));
    final testIndex = _TestWorksIndex(index.filePath);
    final container = ProviderContainer(overrides: [
      downloadPathProvider.overrideWith((ref) => missingRoot.path),
      navidromePathProvider.overrideWith((ref) => targetRoot.path),
      worksIndexProvider.overrideWith((ref) => testIndex),
    ]);
    addTearDown(container.dispose);

    final items = await container.read(worksLibraryServiceProvider).listWorks();
    // 只列出目录仍存在的注册表条目，不产生任何写回
    expect(items, hasLength(1));
    expect(items.single.sourceId, sourceId);
    expect(items.single.trackCount, 1);
    expect(testIndex.upsertCount, 0);

    final kept = await index.get(sourceId);
    expect(kept!.dlPath, dlRoot.path);
    expect(kept.dirName, 'CV-标题');
    final stale = await index.get(staleId);
    expect(stale!.dlPath, dlRoot.path);
    expect(stale.dirName, '旧目录');
  });
}
