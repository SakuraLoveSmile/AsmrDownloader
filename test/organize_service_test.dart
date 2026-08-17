import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/asmr_api.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/api_providers.dart';
import 'package:asmr_downloader/services/cache/cache_database.dart';
import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:asmr_downloader/services/cache/cache_service.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/organize_service.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 测试用 API 替身：按数字 id 返回 workInfo，可配置抛异常。
class FakeAsmrApi extends AsmrApi {
  final Map<String, Map<String, dynamic>> works;
  final Map<String, Uint8List> covers;
  final bool throws;

  FakeAsmrApi({
    this.works = const {},
    this.covers = const {},
    this.throws = false,
  });

  @override
  Future<Map<String, dynamic>?> getWorkInfo(String id) async {
    if (throws) throw Exception('network error');
    return works[id];
  }

  @override
  Future<Uint8List?> getCoverBytes(String url) async => covers[url];
}

/// 构造最小合法 wav（RIFF + WAVE 头，AudioTagWriter 可识别并写标签）。
Uint8List _buildMinimalWav() {
  final fmt = Uint8List.fromList([
    0x01, 0x00, 0x01, 0x00, 0x40, 0x1F, 0x00, 0x00, 0x80, 0x3E, 0x00, 0x00,
    0x02, 0x00, 0x10, 0x00,
  ]);
  final data = List<int>.filled(16, 0);
  final fmtChunk = <int>[
    ...'fmt '.codeUnits,
    ..._u32le(fmt.length),
    ...fmt,
  ];
  final dataChunk = <int>[
    ...'data'.codeUnits,
    ..._u32le(data.length),
    ...data,
  ];
  final body = Uint8List.fromList([...fmtChunk, ...dataChunk]);
  return Uint8List.fromList([
    ...'RIFF'.codeUnits,
    ..._u32le(4 + body.length),
    ...'WAVE'.codeUnits,
    ...body,
  ]);
}

Uint8List _u32le(int v) =>
    Uint8List.fromList([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

String _ascii(Uint8List bytes, int start, int len) =>
    String.fromCharCodes(bytes.sublist(start, start + len));

/// 读取 wav 的 LIST/INFO 子 chunk，返回 id -> 文本（如 IART=artist）。
Map<String, String>? _readListInfo(File file) {
  final bytes = file.readAsBytesSync();
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = _ascii(bytes, offset, 4);
    final size = (bytes[offset + 4] |
            (bytes[offset + 5] << 8) |
            (bytes[offset + 6] << 16) |
            (bytes[offset + 7] << 24)) &
        0x7FFFFFFF;
    if (id == 'LIST' && offset + 8 + size <= bytes.length) {
      final listType = _ascii(bytes, offset + 8, 4);
      if (listType == 'INFO') {
        final result = <String, String>{};
        var pos = offset + 12;
        final end = offset + 8 + size;
        while (pos + 8 <= end) {
          final subId = _ascii(bytes, pos, 4);
          final subSize = (bytes[pos + 4] |
                  (bytes[pos + 5] << 8) |
                  (bytes[pos + 6] << 16) |
                  (bytes[pos + 7] << 24)) &
              0x7FFFFFFF;
          final value = utf8.decode(bytes.sublist(pos + 8, pos + 8 + subSize));
          result[subId] = value;
          pos += 8 + subSize + (subSize.isOdd ? 1 : 0);
        }
        return result;
      }
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  return null;
}

void main() {
  late Directory testBase;
  late Directory dlPath;
  late Directory targetRoot;
  late WorksIndex index;

  WorkEntry entry(String sourceId, {bool dirExists = true, String? organizedAt}) {
    final dirName = '社团-标题$sourceId';
    if (dirExists) {
      final workDir = Directory(p.join(dlPath.path, dirName, sourceId))
        ..createSync(recursive: true);
      Directory(p.join(workDir.path, '音声')).createSync();
      File(p.join(workDir.path, '音声', 'e01_舔耳.wav'))
          .writeAsBytesSync(Uint8List.fromList(List.filled(100, 1)));
    }
    return WorkEntry(
      sourceId: sourceId,
      dlPath: dlPath.path,
      dirName: dirName,
      title: '标题$sourceId',
      cvNames: 'CV1&CV2',
      circleName: '社团',
      organizedAt: organizedAt,
    );
  }

  setUp(() {
    testBase = Directory.systemTemp.createTempSync('organize_service_test');
    dlPath = Directory(p.join(testBase.path, 'dl'))..createSync();
    targetRoot = Directory(p.join(testBase.path, 'navidrome'))..createSync();
    index = WorksIndex(filePath: p.join(testBase.path, 'works_index.json'));
  });

  tearDown(() {
    testBase.deleteSync(recursive: true);
  });

  ProviderContainer makeContainer({
    Map<String, Map<String, dynamic>> works = const {},
    Map<String, Uint8List> covers = const {},
    bool apiThrows = false,
    CacheService? cache,
  }) {
    // 默认内存缓存库（避免测试污染真实应用数据目录）
    final cacheDb = CacheDatabase.forTesting(NativeDatabase.memory());
    addTearDown(cacheDb.close);
    return ProviderContainer(overrides: [
      worksIndexProvider.overrideWith((ref) => index),
      asmrApiProvider.overrideWith(
          (ref) => FakeAsmrApi(works: works, covers: covers, throws: apiThrows)),
      downloadPathProvider.overrideWith((ref) => dlPath.path),
      cacheServiceProvider.overrideWith(
          (ref) => cache ?? CacheService(cacheDb)),
    ]);
  }

  group('字段解析', () {
    test('workInfo 存在时用 workInfo，否则降级', () {
      final info = <String, dynamic>{
        'title': '正式标题',
        'circle': {'name': '真实社团'},
        'vas': [
          {'name': 'CV1'},
          {'name': 'CV2'},
        ],
        'release': '2026-06-09',
        'tags': [
          {'i18n': {'zh-cn': {'name': '舔耳'}}},
        ],
      };
      expect(OrganizeService.resolveTitle(info, 'fallback'), '正式标题');
      expect(OrganizeService.resolveCvNames(info, 'fb'), 'CV1&CV2');
      expect(OrganizeService.resolveCircle(info, 'fb'), '真实社团');
      expect(OrganizeService.resolveRelease(info), '2026-06-09');
      expect(OrganizeService.resolveTags(info), ['舔耳']);

      expect(OrganizeService.resolveTitle(null, 'fallback'), 'fallback');
      expect(OrganizeService.resolveCvNames(null, 'fb'), 'fb');
      expect(OrganizeService.resolveCircle(null, 'fb'), 'fb');
      expect(OrganizeService.resolveRelease(null), '');
      expect(OrganizeService.resolveTags(null), isEmpty);
    });

    test('目录名解析 cv-title', () {
      final r1 = OrganizeService.parseDirName('CV1&CV2-舔耳作品');
      expect(r1.cvNames, 'CV1&CV2');
      expect(r1.title, '舔耳作品');

      final r2 = OrganizeService.parseDirName('无分隔符');
      expect(r2.cvNames, '');
      expect(r2.title, '无分隔符');
    });
  });

  group('organizeWork', () {
    test('源目录不存在返回 null', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final result = await container
          .read(organizeServiceProvider)
          .organizeWork(
        sourceId: 'RJ00001',
        sourceDir: p.join(dlPath.path, '不存在', 'RJ00001'),
        targetRoot: targetRoot.path,
        fallbackTitle: '标题',
        fallbackCvNames: 'CV1',
      );
      expect(result, isNull);
    });

    test('workInfo 为空时用降级字段整理', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final e = entry('RJ00001');

      final result = await container
          .read(organizeServiceProvider)
          .organizeWork(
        sourceId: e.sourceId,
        sourceDir: e.sourceDir,
        targetRoot: targetRoot.path,
        workInfo: null,
        fallbackTitle: e.title,
        fallbackCvNames: e.cvNames,
        fallbackCircle: e.circleName,
      );

      expect(result, isNotNull);
      expect(result!.copied, 1);
      // 目录结构：circle / RJ - cv - title / RJ
      final workDir = p.join(
        targetRoot.path,
        '社团',
        'RJ00001 - CV1&CV2 - 标题RJ00001',
        'RJ00001',
      );
      expect(File(p.join(workDir, 'e01_舔耳.wav')).existsSync(), true);
    });

    test('音频 artist 标签 = CV 声优，而非社团名', () async {
      // 构造合法 wav（让 AudioTagWriter 能写标签）
      final srcDir = Directory(p.join(dlPath.path, '社团-艺术家标签', 'RJ00009'))
        ..createSync(recursive: true);
      final audioDir = Directory(p.join(srcDir.path, '音声'))..createSync();
      File(p.join(audioDir.path, 'e01_舔耳.wav'))
          .writeAsBytesSync(_buildMinimalWav());

      final container = makeContainer();
      addTearDown(container.dispose);

      final info = <String, dynamic>{
        'circle': {'id': 1, 'name': '社团名'},
        'vas': [
          {'name': '声优A'},
          {'name': '声优B'},
        ],
      };
      final result = await container
          .read(organizeServiceProvider)
          .organizeWork(
        sourceId: 'RJ00009',
        sourceDir: srcDir.path,
        targetRoot: targetRoot.path,
        workInfo: info,
        fallbackTitle: '标题',
        fallbackCvNames: 'CV_FALLBACK',
        fallbackCircle: '社团名',
      );
      expect(result, isNotNull);

      // circle 目录仍用社团名，而非 CV
      final outDir = p.join(targetRoot.path, '社团名', 'RJ00009 - 声优A&声优B - 标题', 'RJ00009');
      final outWav = File(p.join(outDir, 'e01_舔耳.wav'));
      expect(outWav.existsSync(), true);

      // artist(IART) = CV；albumartist(TP2/IPLS 映射由写器处理)由 writer 写入
      final list = _readListInfo(outWav);
      expect(list, isNotNull);
      expect(list!['IART'], '声优A&声优B');
    });
  });

  group('organizeAll 批量整理', () {
    test('成功/缺失/已整理过滤/取消', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await index.upsert(entry('RJ00001')); // 目录存在，未整理
      await index.upsert(entry('RJ00002')); // 目录存在，未整理
      await index.upsert(entry('RJ00003', dirExists: false)); // 缺失
      await index.upsert(entry('RJ00004', organizedAt: '2026-08-01T00:00:00.000')); // 已整理

      final progressEvents = <BatchProgress>[];
      final result = await container.read(organizeServiceProvider).organizeAll(
        targetRoot: targetRoot.path,
        onlyUnorganized: true,
        onProgress: progressEvents.add,
        isCancelled: () => false,
      );

      // RJ00003 缺失、RJ00004 被过滤
      expect(result.success, 2);
      expect(result.missing, 1);
      expect(result.failed, 0);
      expect(result.skipped, 0);
      expect(result.cancelled, false);
      expect(result.results.length, 3);
      expect(progressEvents.length, greaterThanOrEqualTo(4)); // 每项 + 结尾
      expect(progressEvents.first.statusMessage, '整理文件中…');

      // 成功项已记录 organizedAt
      expect((await index.get('RJ00001'))!.organizedAt, isNotNull);
      expect((await index.get('RJ00002'))!.organizedAt, isNotNull);
      // 缺失项未标记
      expect(await index.get('RJ00003'), isNotNull);
    });

    test('取消：当前作品完成后停止', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await index.upsert(entry('RJ00001'));
      await index.upsert(entry('RJ00002'));
      await index.upsert(entry('RJ00003'));

      var cancelled = false;
      final result = await container.read(organizeServiceProvider).organizeAll(
        targetRoot: targetRoot.path,
        onlyUnorganized: false,
        onProgress: (p) {
          // 第一个作品处理中（done=0 的进度回调后）请求取消：
          // 当前作品仍完成，下一个不再开始
          if (p.done == 0) cancelled = true;
        },
        isCancelled: () => cancelled,
      );

      expect(result.cancelled, true);
      expect(result.success, 1);
      expect(result.results.length, 1);
    });

    test('重复整理幂等（已最新）', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await index.upsert(entry('RJ00001'));
      await container.read(organizeServiceProvider).organizeAll(
        targetRoot: targetRoot.path,
        onlyUnorganized: false,
        onProgress: (_) {},
        isCancelled: () => false,
      );

      final result = await container.read(organizeServiceProvider).organizeAll(
        targetRoot: targetRoot.path,
        onlyUnorganized: false,
        onProgress: (_) {},
        isCancelled: () => false,
      );

      expect(result.success, 0);
      expect(result.skipped, 1);
    });
  });

  group('自动识别 RJ 号（批量整理）', () {
    /// 在下载目录创建 <dlPath>/<dirName>/<rj>/e01_舔耳.wav
    void createWork(String rj, {String dirName = 'CV1&CV2-测试标题'}) {
      final workDir = Directory(p.join(dlPath.path, dirName, rj))
        ..createSync(recursive: true);
      File(p.join(workDir.path, 'e01_舔耳.wav'))
          .writeAsBytesSync(Uint8List.fromList(List.filled(100, 1)));
    }

    test('空注册表：发现未注册作品并整理入库', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      createWork('RJ100001');

      final result = await container.read(organizeServiceProvider).organizeAll(
        targetRoot: targetRoot.path,
        onlyUnorganized: true,
        onProgress: (_) {},
        isCancelled: () => false,
      );

      expect(result.success, 1);
      expect(result.failed, 0);
      expect(result.missing, 0);
      // 注册表新增条目并标记整理
      final entry = await index.get('RJ100001');
      expect(entry, isNotNull);
      expect(entry!.organizedAt, isNotNull);
      expect(entry.dirName, 'CV1&CV2-测试标题');
      expect(entry.dlPath, dlPath.path);
      // API 无数据 → 目录名降级（cv=CV1&CV2，title=测试标题，circle 兜底 CV）
      final workDir = p.join(
        targetRoot.path,
        'CV1&CV2',
        'RJ100001 - CV1&CV2 - 测试标题',
        'RJ100001',
      );
      expect(File(p.join(workDir, 'e01_舔耳.wav')).existsSync(), true);
    });

    test('API 元数据成功时使用真实标题/CV/社团并回写注册表', () async {
      final container = makeContainer(works: {
        '100001': {
          'title': '真实标题',
          'circle': {'name': '真实社团'},
          'vas': [
            {'name': 'CV_A'},
            {'name': 'CV_B'},
          ],
          'release': '2026-06-09',
          'tags': [
            {'i18n': {'zh-cn': {'name': '舔耳'}}},
          ],
          'mainCoverUrl': '',
        },
      });
      addTearDown(container.dispose);
      createWork('RJ100001');

      final result = await container.read(organizeServiceProvider).organizeAll(
        targetRoot: targetRoot.path,
        onlyUnorganized: true,
        onProgress: (_) {},
        isCancelled: () => false,
      );

      expect(result.success, 1);
      final entry = await index.get('RJ100001');
      expect(entry!.title, '真实标题');
      expect(entry.circleName, '真实社团');
      expect(entry.cvNames, 'CV_A&CV_B');
      expect(entry.releaseDate, '2026-06-09');
      expect(entry.tags, ['舔耳']);
      // 目标目录用 API 元数据
      final workDir = p.join(
        targetRoot.path,
        '真实社团',
        'RJ100001 - CV_A&CV_B - 真实标题',
        'RJ100001',
      );
      expect(File(p.join(workDir, 'e01_舔耳.wav')).existsSync(), true);
    });

    test('API 抛异常时仍按目录名降级整理成功', () async {
      final container = makeContainer(apiThrows: true);
      addTearDown(container.dispose);
      createWork('RJ100001');

      final result = await container.read(organizeServiceProvider).organizeAll(
        targetRoot: targetRoot.path,
        onlyUnorganized: true,
        onProgress: (_) {},
        isCancelled: () => false,
      );

      expect(result.success, 1);
      expect(result.failed, 0);
    });

    test('circle 为空时推送元数据阶段并附带降级原因', () async {
      final container = makeContainer(apiThrows: true);
      addTearDown(container.dispose);
      final source = entry('RJ00005');
      await index.upsert(WorkEntry(
        sourceId: source.sourceId,
        dlPath: source.dlPath,
        dirName: source.dirName,
        title: source.title,
        cvNames: source.cvNames,
      ));

      final progressEvents = <BatchProgress>[];
      final result = await container.read(organizeServiceProvider).organizeAll(
        targetRoot: targetRoot.path,
        onlyUnorganized: true,
        onProgress: progressEvents.add,
        isCancelled: () => false,
      );

      expect(result.success, 1);
      expect(progressEvents.first.statusMessage, '获取元数据中…');
      expect(result.results.single.message, contains('元数据获取失败'));
      expect(result.results.single.message, contains('network error'));
    });

    test('非 RJ 目录、位数不足、隐藏目录不识别', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      Directory(p.join(dlPath.path, '音声资料')).createSync(recursive: true);
      Directory(p.join(dlPath.path, '2024')).createSync();
      Directory(p.join(dlPath.path, 'RJ12345')).createSync(); // 位数不足
      Directory(p.join(dlPath.path, '.hidden', 'RJ200001'))
          .createSync(recursive: true);

      final discovered = await container
          .read(organizeServiceProvider)
          .discoverWorks(dlRoot: dlPath.path, excludeRoot: targetRoot.path);
      expect(discovered, isEmpty);
    });

    test('平铺 RJ 目录（下载根下直接放 RJ 号）也能识别整理', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final workDir = Directory(p.join(dlPath.path, 'RJ300001'))
        ..createSync(recursive: true);
      File(p.join(workDir.path, 'e01_舔耳.wav'))
          .writeAsBytesSync(Uint8List.fromList(List.filled(100, 1)));

      final result = await container.read(organizeServiceProvider).organizeAll(
        targetRoot: targetRoot.path,
        onlyUnorganized: true,
        onProgress: (_) {},
        isCancelled: () => false,
      );

      expect(result.success, 1);
      final entry = await index.get('RJ300001');
      expect(entry!.dirName, '');
      expect(entry.dlPath, dlPath.path);
      expect(entry.sourceDir, p.join(dlPath.path, 'RJ300001'));
    });

    test('注册表路径过期但发现新路径：从新路径整理并修正注册表', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      // 注册表记录旧路径（目录不存在）
      await index.upsert(WorkEntry(
        sourceId: 'RJ400001',
        dlPath: dlPath.path,
        dirName: '旧目录',
        title: '旧标题',
        cvNames: 'CV1',
      ));
      // 实际目录在新位置
      createWork('RJ400001', dirName: '新目录');

      final result = await container.read(organizeServiceProvider).organizeAll(
        targetRoot: targetRoot.path,
        onlyUnorganized: true,
        onProgress: (_) {},
        isCancelled: () => false,
      );

      expect(result.success, 1);
      final entry = await index.get('RJ400001');
      expect(entry!.dirName, '新目录');
      expect(entry.dlPath, dlPath.path);
      expect(entry.organizedAt, isNotNull);
    });

    test('targetRoot 位于下载目录内时其子树不作为源扫描', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final navRoot = Directory(p.join(dlPath.path, 'navidrome'))
        ..createSync();
      // 整理产物结构（circle/album/RJ）不应被识别
      Directory(p.join(navRoot.path, '社团', 'RJ500001 - CV - 标题', 'RJ500001'))
          .createSync(recursive: true);

      final discovered = await container
          .read(organizeServiceProvider)
          .discoverWorks(dlRoot: dlPath.path, excludeRoot: navRoot.path);
      expect(discovered, isEmpty);
    });

    test('同一 sourceId 多目录时取最浅路径', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      Directory(p.join(dlPath.path, '浅层', 'RJ600001'))
          .createSync(recursive: true);
      Directory(p.join(dlPath.path, '深层', '更深', 'RJ600001'))
          .createSync(recursive: true);

      final discovered = await container
          .read(organizeServiceProvider)
          .discoverWorks(dlRoot: dlPath.path, excludeRoot: targetRoot.path);
      expect(discovered.length, 1);
      expect(discovered.first.dirName, '浅层');
    });
  });

  group('缓存优先（organize 复用本地缓存）', () {
    /// 在下载目录创建 <dlPath>/<dirName>/<rj>/e01_舔耳.wav
    void createWork(String rj, {String dirName = 'CV1&CV2-测试标题'}) {
      final workDir = Directory(p.join(dlPath.path, dirName, rj))
        ..createSync(recursive: true);
      File(p.join(workDir.path, 'e01_舔耳.wav'))
          .writeAsBytesSync(Uint8List.fromList(List.filled(100, 1)));
    }

    test('自动识别作品元数据缓存命中时不再请求 API（API 异常也不影响）', () async {
      final cacheDb = CacheDatabase.forTesting(NativeDatabase.memory());
      addTearDown(cacheDb.close);
      final cache = CacheService(cacheDb);
      await cache.saveWorkInfo('RJ100001', {
        'title': '缓存标题',
        'circle': {'name': '缓存社团'},
        'vas': [
          {'name': '缓存CV'},
        ],
        'release': '2026-01-01',
        'tags': [
          {'i18n': {'zh-cn': {'name': '缓存标签'}}},
        ],
        'mainCoverUrl': '',
      });
      final container = makeContainer(apiThrows: true, cache: cache);
      addTearDown(container.dispose);
      createWork('RJ100001');

      final result = await container.read(organizeServiceProvider).organizeAll(
        targetRoot: targetRoot.path,
        onlyUnorganized: true,
        onProgress: (_) {},
        isCancelled: () => false,
      );

      expect(result.success, 1);
      // 注册表回写的是缓存元数据
      final entry = await index.get('RJ100001');
      expect(entry!.title, '缓存标题');
      expect(entry.circleName, '缓存社团');
      expect(entry.cvNames, '缓存CV');
      // 目标目录用缓存元数据
      final workDir = p.join(
        targetRoot.path,
        '缓存社团',
        'RJ100001 - 缓存CV - 缓存标题',
        'RJ100001',
      );
      expect(File(p.join(workDir, 'e01_舔耳.wav')).existsSync(), true);
    });

    test('注册表 circle 为空时，organizeEntry 使用缓存补齐社团名', () async {
      final cacheDb = CacheDatabase.forTesting(NativeDatabase.memory());
      addTearDown(cacheDb.close);
      final cache = CacheService(cacheDb);
      await cache.saveWorkInfo('RJ200001', {
        'title': '缓存标题',
        'circle': {'name': '缓存社团'},
        'vas': [
          {'name': '缓存CV'},
        ],
      });
      final container = makeContainer(apiThrows: true, cache: cache);
      addTearDown(container.dispose);
      createWork('RJ200001');
      final source = WorkEntry(
        sourceId: 'RJ200001',
        dlPath: dlPath.path,
        dirName: 'CV1&CV2-测试标题',
        title: '旧标题',
        cvNames: '旧CV',
      );

      final outcome = await container.read(organizeServiceProvider).organizeEntry(
            source,
            targetRoot: targetRoot.path,
          );

      expect(outcome.resolvedEntry.circleName, '缓存社团');
      expect(
        File(p.join(
          targetRoot.path,
          '缓存社团',
          'RJ200001 - 缓存CV - 缓存标题',
          'RJ200001',
          'e01_舔耳.wav',
        )).existsSync(),
        isTrue,
      );
    });

    test('注册表 circle 为空时，缓存未命中则在线补齐', () async {
      final container = makeContainer(works: {
        '200002': {
          'title': '在线标题',
          'circle': {'name': '在线社团'},
          'vas': [
            {'name': '在线CV'},
          ],
        },
      });
      addTearDown(container.dispose);
      createWork('RJ200002');
      final source = WorkEntry(
        sourceId: 'RJ200002',
        dlPath: dlPath.path,
        dirName: 'CV1&CV2-测试标题',
        title: '旧标题',
        cvNames: '旧CV',
      );

      final outcome = await container.read(organizeServiceProvider).organizeEntry(
            source,
            targetRoot: targetRoot.path,
          );

      expect(outcome.resolvedEntry.circleName, '在线社团');
      expect(
        File(p.join(
          targetRoot.path,
          '在线社团',
          'RJ200002 - 在线CV - 在线标题',
          'RJ200002',
          'e01_舔耳.wav',
        )).existsSync(),
        isTrue,
      );
    });

    test('补齐失败时仍使用 CV 顶层兜底', () async {
      final container = makeContainer(apiThrows: true);
      addTearDown(container.dispose);
      createWork('RJ200003');
      final source = WorkEntry(
        sourceId: 'RJ200003',
        dlPath: dlPath.path,
        dirName: 'CV1&CV2-测试标题',
        title: '',
        cvNames: '',
      );

      final outcome = await container.read(organizeServiceProvider).organizeEntry(
            source,
            targetRoot: targetRoot.path,
          );

      expect(outcome.resolvedEntry.circleName, isEmpty);
      expect(outcome.metadataNote, contains('元数据获取失败'));
      expect(outcome.metadataNote, contains('network error'));
      expect(
        File(p.join(
          targetRoot.path,
          'CV1&CV2',
          'RJ200003 - CV1&CV2 - 测试标题',
          'RJ200003',
          'e01_舔耳.wav',
        )).existsSync(),
        isTrue,
      );
    });

    test('汉化版 circle 跟踪原版时缓存优先（缓存命中不请求 API）', () async {
      final cacheDb = CacheDatabase.forTesting(NativeDatabase.memory());
      addTearDown(cacheDb.close);
      final cache = CacheService(cacheDb);
      // 原版 RJ01618607 已在缓存中（此前搜索/浏览过）
      await cache.saveWorkInfo('RJ01618607', {
        'circle': {'name': '原版社团'},
      });
      final container = makeContainer(apiThrows: true, cache: cache);
      addTearDown(container.dispose);

      final e = entry('RJ999999');
      final translatedWorkInfo = <String, dynamic>{
        'title': '【简体中文版】测试',
        'circle': {'name': '汉化组'},
        'translation_info': {
          'is_original': false,
          'original_workno': 'RJ01618607',
        },
        'other_language_editions_in_db': [
          {'id': 1618607, 'source_id': 'RJ01618607', 'is_original': true},
        ],
      };

      final result = await container.read(organizeServiceProvider).organizeWork(
        sourceId: e.sourceId,
        sourceDir: e.sourceDir,
        targetRoot: targetRoot.path,
        workInfo: translatedWorkInfo,
        fallbackTitle: '测试标题',
        fallbackCvNames: 'CV1&CV2',
        fallbackCircle: '汉化组',
      );

      expect(result, isNotNull);
      // artist 使用缓存中的原版社团名（API 抛异常也不影响）；
      // 标题来自 workInfo 本体（resolveTitle 优先 workInfo）
      final workDir = p.join(
        targetRoot.path,
        '原版社团',
        'RJ999999 - CV1&CV2 - 【简体中文版】测试',
        'RJ999999',
      );
      expect(File(p.join(workDir, 'e01_舔耳.wav')).existsSync(), true);
    });
  });
}
