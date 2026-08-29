import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/services/asmr_repo/parse_tracks.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/tracks_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/work_info_providers.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/download/download_queue.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:asmr_downloader/utils/json_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 本地文件服务器：为每个作品提供独立的下载文件，便于验证队列按序落盘。
class _TestServer {
  _TestServer._(this.server, this.workFiles, this.badSourceIds, this.delay);

  final HttpServer server;
  // sourceId -> {path: bytes}
  final Map<String, Map<String, Uint8List>> workFiles;

  /// 这些作品的音轨指向服务器上不存在的路径（/bad/...），触发下载失败。
  final Set<String> badSourceIds;
  final Duration delay;

  int activeRequests = 0;

  static Future<_TestServer> start({
    Duration delay = Duration.zero,
    required Map<String, Map<String, Uint8List>> workFiles,
    Set<String> badSourceIds = const {},
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final testServer = _TestServer._(server, workFiles, badSourceIds, delay);
    server.listen(testServer._handle);
    return testServer;
  }

  String url(String path) => 'http://127.0.0.1:${server.port}$path';

  /// 构建指定作品的音轨树原始数据（getTrackItems 可解析）。
  /// badSourceIds 中的作品指向 /bad/... 路径（服务器 404），其余作品正常。
  List<dynamic> tracksFor(String sourceId) {
    if (badSourceIds.contains(sourceId)) {
      return [
        {
          'title': '${sourceId}_01.bin',
          'type': 'audio',
          'hash': '${sourceId}_01',
          'mediaStreamUrl': url('/bad/${sourceId}_01.bin'),
          'mediaDownloadUrl': url('/bad/${sourceId}_01.bin'),
          'size': 1024,
        },
      ];
    }
    final files = workFiles[sourceId]!;
    return [
      for (final entry in files.entries)
        {
          'title': p.basename(entry.key),
          'type': 'audio',
          'hash': '${sourceId}_${p.basename(entry.key)}',
          'mediaStreamUrl': url(entry.key),
          'mediaDownloadUrl': url(entry.key),
          'size': entry.value.length,
        },
    ];
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    activeRequests++;
    try {
      await Future<void>.delayed(delay);

      // badSourceIds 的作品音轨指向 /bad/... 路径：
      // 返回 416（Range Not Satisfiable）触发立即失败而非无限重试，
      // 与 MultiThreadDownloader 的 416 短路逻辑一致。
      if (path.startsWith('/bad/')) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        await request.response.close();
        return;
      }

      // 在所有作品的文件里查找内容
      Uint8List? content;
      for (final files in workFiles.values) {
        if (files.containsKey(path)) {
          content = files[path];
          break;
        }
      }
      if (content == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentLength = content.length;
      request.response.add(content);
      await request.response.close();
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {}
    } finally {
      activeRequests--;
    }
  }

  Future<void> close() => server.close(force: true);
}

Uint8List _makeContent(int size, int seed) {
  final bytes = Uint8List(size);
  for (var i = 0; i < size; i++) {
    bytes[i] = (i + seed) % 251;
  }
  return bytes;
}

/// 各作品的下载文件集合：sourceId -> {path -> bytes}。
/// 路径键形如 /RJ00001_01.bin，与 tracksFor 生成的文件一一对应。
Map<String, Map<String, Uint8List>> _workFilesFor(List<String> sourceIds) {
  final map = <String, Map<String, Uint8List>>{};
  for (var i = 0; i < sourceIds.length; i++) {
    final sid = sourceIds[i];
    map[sid] = {
      '/${sid}_01.bin': _makeContent(4 * 1024, i * 10 + 1),
      '/${sid}_02.bin': _makeContent(4 * 1024, i * 10 + 2),
    };
  }
  return map;
}

/// 各作品的目录名（cv-标题 形式，由 voiceWorkPathProvider 推导）。
/// 这里通过 titleProvider override 控制目录名，使其稳定可预期。
Map<String, String> _workTitles(List<String> sourceIds) {
  final map = <String, String>{};
  for (var i = 0; i < sourceIds.length; i++) {
    map[sourceIds[i]] = '作品${sourceIds[i]}';
  }
  return map;
}

ProviderContainer _createContainer(
  Directory tempDir,
  _TestServer server,
  List<String> sourceIds, {
  Map<String, Set<String>>? selectedTrackIdsBySource,
}) {
  final titles = _workTitles(sourceIds);
  final queueFilePath = p.join(tempDir.path, 'download_queue.json');

  final container = ProviderContainer(overrides: [
    configFileProvider.overrideWithValue(
      JsonStorage(filePath: p.join(tempDir.path, 'config.json')),
    ),
    downloadPathProvider
        .overrideWith((ref) => p.join(tempDir.path, 'downloads')),
    // 队列文件指向临时目录，避免污染应用数据目录
    downloadQueueFilePathProvider.overrideWithValue(queueFilePath),
    // workInfo：返回各作品元数据（驱动 title/cv/circle 等降级链）。
    // vas 留空，使下载目录名为纯标题，便于断言路径。
    workInfoProvider.overrideWith((ref) async {
      final sid = ref.watch(sourceIdProvider) ?? '';
      return {
        'title': titles[sid] ?? sid,
        'circle': {'name': '社团$sid'},
        'vas': <Object>[
          {'name': 'CV$sid'},
        ],
        'tags': <Object>[
          {
            'i18n': {
              'zh-cn': {'name': '标签$sid'},
            }
          },
        ],
        'release': '2024-01-01',
        'mainCoverUrl': '',
      };
    }),
    // rawTracks：按 sourceId 返回该作品的音轨树
    rawTracksProvider.overrideWith((ref) async {
      final sid = ref.watch(sourceIdProvider) ?? '';
      return server.tracksFor(sid);
    }),
    // rootFolder：按 sourceId 重建并全选文件（队列切换作品时自动重算）
    rootFolderProvider.overrideWith((ref) {
      final sid = ref.watch(sourceIdProvider);
      if (sid == null) return null;
      final raw = ref.watch(rawTracksProvider);
      return raw.maybeWhen(
        data: (data) {
          if (data == null) return null;
          final folder = Folder(id: sid, title: sid)
            ..children = getTrackItems(data);
          if (selectedTrackIdsBySource == null ||
              !selectedTrackIdsBySource.containsKey(sid)) {
            folder.setSelection(true);
          } else {
            applySelectedFileIds(folder, selectedTrackIdsBySource[sid]);
          }
          return folder;
        },
        orElse: () => null,
      );
    }),
    worksIndexProvider.overrideWithValue(
      WorksIndex(filePath: p.join(tempDir.path, 'works_index.json')),
    ),
  ]);
  addTearDown(container.dispose);
  return container;
}

/// 作品文件落盘路径：downloads/{cv-title}/{sourceId}/{basename}
/// 与 voiceWorkPathProvider 的目录名规则一致：cv&...&cvn-title。
String _workFilePath(Directory tempDir, String sourceId, String basename) {
  final dirName = 'CV$sourceId-作品$sourceId';
  return p.join(
    tempDir.path,
    'downloads',
    dirName,
    sourceId,
    basename,
  );
}

void main() {
  test('Notifier 启动恢复与立即加入队列不会丢失磁盘条目', () async {
    final tempDir =
        Directory.systemTemp.createTempSync('dl_queue_notifier_ready');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final filePath = p.join(tempDir.path, 'download_queue.json');
    File(filePath)
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({
        'items': ['RJ00001']
      }));

    final container = ProviderContainer(
      overrides: [downloadQueueFilePathProvider.overrideWithValue(filePath)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(downloadQueueProvider.notifier);
    expect(await notifier.add('RJ00002'), isTrue);
    expect(
      container.read(downloadQueueProvider).map((item) => item.sourceId),
      ['RJ00001', 'RJ00002'],
    );
    expect(
      (await DownloadQueue(filePath: filePath).list())
          .map((item) => item.sourceId),
      ['RJ00001', 'RJ00002'],
    );
  });

  test('队列去重与持久化：add 两次只保留一个，重新构造后条目仍在', () async {
    final tempDir = Directory.systemTemp.createTempSync('dl_queue_test_dedup');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final filePath = p.join(tempDir.path, 'download_queue.json');

    final queue = DownloadQueue(filePath: filePath);
    final added1 = await queue.add('RJ00001');
    final added2 = await queue.add('RJ00001');
    expect(added1, isTrue);
    expect(added2, isFalse);
    expect((await queue.list()).map((item) => item.sourceId), ['RJ00001']);

    await queue.add('RJ00002');
    expect((await queue.list()).map((item) => item.sourceId),
        ['RJ00001', 'RJ00002']);

    // 重新构造（模拟重启）：条目应从磁盘恢复
    final queue2 = DownloadQueue(filePath: filePath);
    expect((await queue2.list()).map((item) => item.sourceId),
        ['RJ00001', 'RJ00002']);

    // popFront 取出队首并落盘
    expect((await queue2.popFront())?.sourceId, 'RJ00001');
    expect((await queue2.list()).map((item) => item.sourceId), ['RJ00002']);
  });

  test('崩溃恢复：claim 占用队首，重启后 restoreCurrent 放回队首', () async {
    final tempDir = Directory.systemTemp.createTempSync('dl_queue_test_crash');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final filePath = p.join(tempDir.path, 'download_queue.json');

    final queue = DownloadQueue(filePath: filePath);
    await queue.add('RJ00001');
    await queue.add('RJ00002');

    // 模拟下载器占用队首开始下载
    final claimed = await queue.claimFrontIf('RJ00001');
    expect(claimed?.sourceId, 'RJ00001');
    expect((await queue.list()).map((e) => e.sourceId), ['RJ00002']);

    // 模拟应用崩溃后重启：占用标记仍在文件里
    final queue2 = DownloadQueue(filePath: filePath);
    expect((await queue2.list()).map((e) => e.sourceId), ['RJ00002']);
    await queue2.restoreCurrent();
    expect(
        (await queue2.list()).map((e) => e.sourceId), ['RJ00001', 'RJ00002']);
    // 恢复后占用标记清除（幂等：再次恢复无副作用）
    await queue2.restoreCurrent();
    expect(
        (await queue2.list()).map((e) => e.sourceId), ['RJ00001', 'RJ00002']);
  });

  test('作品出结果后 releaseCurrent 清除占用，不回插队首', () async {
    final tempDir =
        Directory.systemTemp.createTempSync('dl_queue_test_release');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final filePath = p.join(tempDir.path, 'download_queue.json');

    final queue = DownloadQueue(filePath: filePath);
    await queue.add('RJ00001');
    await queue.add('RJ00002');
    await queue.claimFrontIf('RJ00001');

    // 下载完成/失败：释放占用，RJ00001 不回到队列
    await queue.releaseCurrent();
    final queue2 = DownloadQueue(filePath: filePath);
    await queue2.restoreCurrent();
    expect((await queue2.list()).map((e) => e.sourceId), ['RJ00002']);
  });

  test('队列文件损坏时自动从 .bak 恢复（原子写回退）', () async {
    final tempDir =
        Directory.systemTemp.createTempSync('dl_queue_test_recover');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final filePath = p.join(tempDir.path, 'download_queue.json');

    final queue = DownloadQueue(filePath: filePath);
    await queue.add('RJ00001');
    await queue.add('RJ00002');

    // 模拟异常退出留下的半截 JSON
    await File(filePath).writeAsString('{"items": ["RJ0000');

    // 重新构造（模拟重启）：应回退 .bak 恢复上一次完好内容
    // （.bak 是上一次成功写入的快照：RJ00002 那次损坏的写入丢失）
    final queue2 = DownloadQueue(filePath: filePath);
    expect((await queue2.list()).map((item) => item.sourceId), ['RJ00001']);
    // 正式文件已自动恢复，可继续正常读写
    await queue2.add('RJ00003');
    expect((await queue2.list()).map((item) => item.sourceId),
        ['RJ00001', 'RJ00003']);
  });

  test('队列写失败向上抛出，不静默假成功', () async {
    final tempDir =
        Directory.systemTemp.createTempSync('dl_queue_test_writefail');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    // 同名路径是目录：写文件必然失败
    final badPath = p.join(tempDir.path, 'download_queue.json');
    Directory(badPath).createSync();

    final queue = DownloadQueue(filePath: badPath);
    await expectLater(queue.add('RJ00001'), throwsException);
  });

  test('队列持久化入队时的勾选音轨，并兼容旧版 sourceId 格式', () async {
    final tempDir =
        Directory.systemTemp.createTempSync('dl_queue_test_selection');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final filePath = p.join(tempDir.path, 'download_queue.json');

    final queue = DownloadQueue(filePath: filePath);
    expect(
      await queue.add(
        'RJ00001',
        selectedTrackIds: ['track-a', 'track-b'],
      ),
      isTrue,
    );

    final item = (await queue.list()).single;
    expect(item.sourceId, 'RJ00001');
    expect(item.selectedTrackIds, ['track-a', 'track-b']);
    final raw = jsonDecode(File(filePath).readAsStringSync()) as Map;
    expect(raw['items'][0]['selectedTrackIds'], ['track-a', 'track-b']);

    // 旧版只有 sourceId，读取时用 null 表示兼容行为：恢复为全选。
    File(filePath).writeAsStringSync(
      jsonEncode({
        'items': ['RJ00002']
      }),
    );
    final legacyItem = (await DownloadQueue(filePath: filePath).list()).single;
    expect(legacyItem.sourceId, 'RJ00002');
    expect(legacyItem.selectedTrackIds, isNull);
  });

  test('队列顺序执行：下载中 enqueue 两个作品，按序下载且文件均落盘', () async {
    final sourceIds = ['RJ00001', 'RJ00002', 'RJ00003'];
    final server = await _TestServer.start(
      workFiles: _workFilesFor(sourceIds),
    );
    addTearDown(server.close);

    final tempDir = Directory.systemTemp.createTempSync('dl_queue_test_order');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final container = _createContainer(tempDir, server, sourceIds);

    // 初始搜索第一个作品
    await container.read(uiServiceProvider).search('RJ00001');
    await container.read(workInfoProvider.future);
    await container.read(rawTracksProvider.future);

    // 下载中把第 2、3 个作品加入队列
    final runFuture = container.read(downloadManagerProvider).run();
    // 等待下载真正开始
    while (container.read(dlStatusProvider) != DownloadStatus.downloading) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await container.read(downloadQueueProvider.notifier).add('RJ00002');
    await container.read(downloadQueueProvider.notifier).add('RJ00003');
    expect(
      container.read(downloadQueueProvider).map((item) => item.sourceId),
      ['RJ00002', 'RJ00003'],
    );

    await runFuture;

    // 三个作品文件均落盘
    for (final sid in sourceIds) {
      for (final basename in ['${sid}_01.bin', '${sid}_02.bin']) {
        final file = File(_workFilePath(tempDir, sid, basename));
        expect(file.existsSync(), isTrue, reason: '$basename should exist');
      }
    }
    // 队列清空
    expect(container.read(downloadQueueProvider), isEmpty);
    expect(container.read(dlStatusProvider), DownloadStatus.completed);
  });

  test('失败跳过：队首作品下载失败，后续作品继续且 snackbar 计数正确', () async {
    final sourceIds = ['RJ00001', 'RJ00002'];
    // 第一个作品标记为 bad：其音轨指向服务器上不存在的 /bad/... 路径，触发下载失败
    final server = await _TestServer.start(
      workFiles: _workFilesFor(sourceIds),
      badSourceIds: {'RJ00001'},
    );
    addTearDown(server.close);

    final tempDir = Directory.systemTemp.createTempSync('dl_queue_test_fail');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final container = _createContainer(tempDir, server, sourceIds);

    // 直接入队两个作品，用 startFromQueue 启动（无当前搜索场景）
    await container.read(downloadQueueProvider.notifier).add('RJ00001');
    await container.read(downloadQueueProvider.notifier).add('RJ00002');

    await container.read(downloadManagerProvider).startFromQueue();

    // 失败作品文件不存在，第二个作品文件落盘
    expect(
      File(_workFilePath(tempDir, 'RJ00001', 'RJ00001_01.bin')).existsSync(),
      isFalse,
    );
    for (final basename in ['RJ00002_01.bin', 'RJ00002_02.bin']) {
      expect(
        File(_workFilePath(tempDir, 'RJ00002', basename)).existsSync(),
        isTrue,
      );
    }
    // 队列清空
    expect(container.read(downloadQueueProvider), isEmpty);
  });

  test('取消停止：下载中取消，队列条目保留且不再启动下一个', () async {
    final sourceIds = ['RJ00001', 'RJ00002'];
    final server = await _TestServer.start(
      workFiles: _workFilesFor(sourceIds),
      delay: const Duration(seconds: 2),
    );
    addTearDown(server.close);

    final tempDir = Directory.systemTemp.createTempSync('dl_queue_test_cancel');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final container = _createContainer(tempDir, server, sourceIds);

    await container.read(uiServiceProvider).search('RJ00001');
    await container.read(workInfoProvider.future);
    await container.read(rawTracksProvider.future);

    // 入队第二个作品
    await container.read(downloadQueueProvider.notifier).add('RJ00002');

    final runFuture = container.read(downloadManagerProvider).run();
    while (server.activeRequests == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    container.read(downloadManagerProvider).cancelAllDownload();
    await runFuture;

    while (server.activeRequests > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(container.read(dlStatusProvider), DownloadStatus.canceled);
    // 第一个作品未完成
    expect(
      File(_workFilePath(tempDir, 'RJ00001', 'RJ00001_01.bin')).existsSync(),
      isFalse,
    );
    // 队列条目保留
    expect(
      container.read(downloadQueueProvider).map((item) => item.sourceId),
      ['RJ00002'],
    );
    // 第二个作品文件未下载
    expect(
      File(_workFilePath(tempDir, 'RJ00002', 'RJ00002_01.bin')).existsSync(),
      isFalse,
    );
  });

  test('从队列下载时恢复入队时的部分勾选，只下载选中的音轨', () async {
    final sourceIds = ['RJ00001', 'RJ00002'];
    final server = await _TestServer.start(
      workFiles: _workFilesFor(sourceIds),
    );
    addTearDown(server.close);

    final tempDir =
        Directory.systemTemp.createTempSync('dl_queue_test_selection_restore');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final selectedId = 'RJ00002_RJ00002_01.bin';
    final container = _createContainer(
      tempDir,
      server,
      sourceIds,
      selectedTrackIdsBySource: {'RJ00002': <String>{}},
    );

    await container.read(downloadQueueProvider.notifier).add(
      'RJ00002',
      selectedTrackIds: [selectedId],
    );

    await container.read(downloadManagerProvider).startFromQueue();

    expect(
      File(_workFilePath(tempDir, 'RJ00002', 'RJ00002_01.bin')).existsSync(),
      isTrue,
    );
    expect(
      File(_workFilePath(tempDir, 'RJ00002', 'RJ00002_02.bin')).existsSync(),
      isFalse,
    );
    expect(container.read(downloadQueueProvider), isEmpty);
  });

  test('注册表快照：下载中切换搜索作品，works_index 写入快照作品的数据', () async {
    final sourceIds = ['RJ00001', 'RJ00002'];
    final server = await _TestServer.start(
      workFiles: _workFilesFor(sourceIds),
    );
    addTearDown(server.close);

    final tempDir =
        Directory.systemTemp.createTempSync('dl_queue_test_snapshot');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final container = _createContainer(tempDir, server, sourceIds);

    // 初始搜索并开始下载第一个作品
    await container.read(uiServiceProvider).search('RJ00001');
    await container.read(workInfoProvider.future);
    await container.read(rawTracksProvider.future);

    final runFuture = container.read(downloadManagerProvider).run();
    while (container.read(dlStatusProvider) != DownloadStatus.downloading) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    // 下载中切换搜索到第二个作品（模拟用户搜索新作品）
    await container.read(uiServiceProvider).search('RJ00002');
    await container.read(workInfoProvider.future);
    await container.read(rawTracksProvider.future);

    await runFuture;

    // 注册表写入的是快照（第一个）作品的数据，而非下载中被搜索切走的第二个
    final entry = await container.read(worksIndexProvider).get('RJ00001');
    expect(entry, isNotNull);
    expect(entry!.title, '作品RJ00001');
    expect(entry.circleName, '社团RJ00001');
    expect(entry.cvNames, 'CVRJ00001');
    // 第二个作品不应被写入注册表（本次只下载了第一个）
    final entry2 = await container.read(worksIndexProvider).get('RJ00002');
    expect(entry2, isNull);
  });
}
