import 'dart:io';
import 'dart:typed_data';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/work_info_providers.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/download/download_queue.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:asmr_downloader/utils/json_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 本地文件服务器：按路径返回预置字节，记录所有请求路径。
class _TestServer {
  _TestServer._(this.server, this.contents, this.delay);

  final HttpServer server;
  final Map<String, Uint8List> contents;
  final Duration delay;

  final List<String> requestedPaths = [];

  static Future<_TestServer> start({
    Duration delay = Duration.zero,
    required Map<String, Uint8List> contents,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final testServer = _TestServer._(server, contents, delay);
    server.listen(testServer._handle);
    return testServer;
  }

  String url(String path) => 'http://127.0.0.1:${server.port}$path';

  Future<void> _handle(HttpRequest request) async {
    requestedPaths.add(request.uri.path);
    try {
      await Future<void>.delayed(delay);
      final content = contents[request.uri.path];
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

// ---- 可变测试状态：模拟「下载中搜索切换作品」 ----

final testSourceId = StateProvider<String>((ref) => 'RJ00001');
final testWorkInfo = StateProvider<Map<String, dynamic>>((ref) => {});
final testRootFolder = StateProvider<Folder?>((ref) => null);
final testCoverBytes = StateProvider<Uint8List?>((ref) => null);

void main() {
  late Directory tempDir;
  late _TestServer server;
  late Uint8List contentA;
  late Uint8List contentB;
  late Uint8List coverA;
  late Uint8List coverB;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('download_context_test');
    contentA = _makeContent(8 * 1024, 1);
    contentB = _makeContent(8 * 1024, 200);
    coverA = _makeContent(512, 7);
    coverB = _makeContent(512, 9);
    server = await _TestServer.start(
      delay: const Duration(milliseconds: 30),
      contents: {
        '/a1.bin': contentA,
        '/b1.bin': contentB,
        '/coverA.jpg': coverA,
        '/coverB.jpg': coverB,
      },
    );
  });

  tearDown(() {
    server.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Map<String, dynamic> workInfoOf(String title, String circle, String cover) =>
      {
        'title': title,
        'circle': {'name': circle},
        'vas': <Object>[],
        'tags': <Object>[],
        'release': '2025-01-01',
        'mainCoverUrl': cover,
      };

  Folder rootOf(String sourceId, String contentPath) {
    final root = Folder(id: sourceId, title: sourceId);
    root.children.add(FileAsset(
      id: contentPath,
      type: 'audio',
      title: p.basename(contentPath),
      mediaStreamUrl: server.url(contentPath),
      mediaDownloadUrl: server.url(contentPath),
      size: server.contents[contentPath]!.length,
    )..selected = true);
    return root;
  }

  /// 把搜索状态切到作品 B（下载中模拟用户搜索了另一个作品）
  void switchToWorkB(ProviderContainer container) {
    container
      ..read(testSourceId.notifier).state = 'RJ00002'
      ..read(testWorkInfo.notifier).state =
          workInfoOf('测试作品B', '社团B', server.url('/coverB.jpg'))
      ..read(testRootFolder.notifier).state = rootOf('RJ00002', '/b1.bin')
      ..read(testCoverBytes.notifier).state = null;
  }

  Future<ProviderContainer> createContainer({
    required void Function(ProviderContainer) onCircleNameResolve,
    Uint8List? coverBytes,
  }) async {
    late final ProviderContainer container;
    container = ProviderContainer(overrides: [
      configFileProvider.overrideWithValue(
        JsonStorage(filePath: p.join(tempDir.path, 'config.json')),
      ),
      downloadPathProvider
          .overrideWith((ref) => p.join(tempDir.path, 'downloads')),
      worksIndexProvider.overrideWithValue(
        WorksIndex(filePath: p.join(tempDir.path, 'works_index.json')),
      ),
      sourceIdProvider.overrideWith((ref) => ref.watch(testSourceId)),
      workInfoProvider.overrideWith((ref) async => ref.watch(testWorkInfo)),
      rootFolderProvider.overrideWith((ref) => ref.watch(testRootFolder)),
      coverBytesProvider.overrideWith((ref) async => ref.watch(testCoverBytes)),
      // 社团名解析存在异步间隙（汉化跟踪需联网）；在此间隙触发搜索切换，
      // 正好覆盖旧实现「快照 await 之后重读全局状态」的竞态窗口。
      circleNameProvider.overrideWith((ref) async {
        // 先让出 provider 构建帧，再切换搜索状态（riverpod 禁止构建期改状态）
        await Future<void>.delayed(Duration.zero);
        onCircleNameResolve(ref.container as ProviderContainer);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return '社团A';
      }),
    ]);
    container
      ..read(testSourceId.notifier).state = 'RJ00001'
      ..read(testWorkInfo.notifier).state =
          workInfoOf('测试作品A', '社团A', server.url('/coverA.jpg'))
      ..read(testRootFolder.notifier).state = rootOf('RJ00001', '/a1.bin')
      ..read(testCoverBytes.notifier).state = coverBytes
      ..read(dlCoverProvider.notifier).state = true
      ..read(autoOrganizeProvider.notifier).state = true
      ..read(downloadThreadsProvider.notifier).state = 1
      ..read(parallelDownloadCountProvider.notifier).state = 1
      ..read(navidromePathProvider.notifier).state =
          p.join(tempDir.path, 'navidrome');
    // 预热元数据，与真实场景一致：作品信息加载完成后才开始下载
    await container.read(workInfoProvider.future);
    await container.read(coverBytesProvider.future);
    return container;
  }

  Directory workDirOf(String title) =>
      Directory(p.join(tempDir.path, 'downloads', title));

  test('下载 A 的快照间隙搜索切到 B：任务、封面、注册表、自动整理全部属于 A', () async {
    var flipped = false;
    final container = await createContainer(onCircleNameResolve: (c) {
      if (!flipped) {
        flipped = true;
        switchToWorkB(c);
      }
    });
    addTearDown(container.dispose);

    await container.read(downloadManagerProvider).run();

    // 下载状态与指示器属于 A
    expect(container.read(dlStatusProvider), DownloadStatus.completed);
    expect(container.read(lastDownloadSourceIdProvider), 'RJ00001');
    expect(container.read(currentDownloadingSourceIdProvider), isNull);

    // 下载目录属于 A，B 未产生任何下载副作用
    expect(
      File(p.join(workDirOf('测试作品A').path, 'RJ00001', 'a1.bin'))
          .readAsBytesSync(),
      contentA,
    );
    expect(workDirOf('测试作品B').existsSync(), isFalse);
    expect(server.requestedPaths, contains('/a1.bin'));
    expect(server.requestedPaths, isNot(contains('/b1.bin')));
    expect(server.requestedPaths, isNot(contains('/coverB.jpg')));

    // 封面按快照 URL 下载（coverBytes 未就绪时走网络兜底）
    expect(
      File(p.join(workDirOf('测试作品A').path, 'RJ00001', 'RJ00001_cover.jpg'))
          .readAsBytesSync(),
      coverA,
    );
    expect(server.requestedPaths, contains('/coverA.jpg'));

    // 注册表记录属于 A
    final entry = await container.read(worksIndexProvider).get('RJ00001');
    expect(entry, isNotNull);
    expect(entry!.title, '测试作品A');
    expect(entry.circleName, '社团A');
    expect(p.basename(entry.dirName), '测试作品A');
    expect(await container.read(worksIndexProvider).get('RJ00002'), isNull);

    // 自动整理使用 A 的快照元数据，产物落在 A 的社团/专辑目录
    final organizedFile = File(p.join(
      tempDir.path,
      'navidrome',
      '社团A',
      'RJ00001 - 测试作品A',
      'RJ00001',
      'a1.bin',
    ));
    expect(organizedFile.readAsBytesSync(), contentA);
    expect(
      File(p.join(
        tempDir.path,
        'navidrome',
        '社团A',
        'RJ00001 - 测试作品A',
        'RJ00001',
        'cover.jpg',
      )).readAsBytesSync(),
      coverA,
    );
  });

  test('下载完成后搜索切到 B：自动整理与注册表仍使用 A', () async {
    final container = await createContainer(
      onCircleNameResolve: (_) {},
      coverBytes: coverA,
    );
    addTearDown(container.dispose);

    final runFuture = container.read(downloadManagerProvider).run();
    // 第一个文件请求发出后（下载中）把搜索切到 B
    while (server.requestedPaths.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    switchToWorkB(container);
    await runFuture;

    expect(container.read(dlStatusProvider), DownloadStatus.completed);
    expect(container.read(lastDownloadSourceIdProvider), 'RJ00001');

    // 下载目录属于 A
    expect(
      File(p.join(workDirOf('测试作品A').path, 'RJ00001', 'a1.bin'))
          .readAsBytesSync(),
      contentA,
    );
    expect(workDirOf('测试作品B').existsSync(), isFalse);
    expect(server.requestedPaths, isNot(contains('/b1.bin')));
    expect(server.requestedPaths, isNot(contains('/coverB.jpg')));

    // 注册表与自动整理产物属于 A
    final entry = await container.read(worksIndexProvider).get('RJ00001');
    expect(entry, isNotNull);
    expect(entry!.title, '测试作品A');
    expect(await container.read(worksIndexProvider).get('RJ00002'), isNull);
    expect(
      File(p.join(
        tempDir.path,
        'navidrome',
        '社团A',
        'RJ00001 - 测试作品A',
        'RJ00001',
        'a1.bin',
      )).readAsBytesSync(),
      contentA,
    );
    expect(
      File(p.join(
        tempDir.path,
        'navidrome',
        '社团A',
        'RJ00001 - 测试作品A',
        'RJ00001',
        'cover.jpg',
      )).readAsBytesSync(),
      coverA,
    );
  });
}
