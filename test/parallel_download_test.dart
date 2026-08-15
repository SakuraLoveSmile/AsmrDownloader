import 'dart:io';
import 'dart:typed_data';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/work_info_providers.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:asmr_downloader/utils/json_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 简单的本地文件服务器，用于观察文件级并行下载的并发度。
class _TestServer {
  _TestServer._(this.server, this.contents, this.delay);

  final HttpServer server;
  final Map<String, Uint8List> contents;
  final Duration delay;

  int activeRequests = 0;
  int maxActiveRequests = 0;

  static Future<_TestServer> start({
    Duration delay = Duration.zero,
    Map<String, Uint8List>? contents,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final testServer = _TestServer._(
      server,
      contents ??
          {
            '/f1.bin': _makeContent(8 * 1024, 1),
            '/f2.bin': _makeContent(8 * 1024, 2),
            '/f3.bin': _makeContent(8 * 1024, 3),
          },
      delay,
    );
    server.listen(testServer._handle);
    return testServer;
  }

  String url(String path) => 'http://127.0.0.1:${server.port}$path';

  Uint8List content(String path) => contents[path]!;

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    activeRequests++;
    if (activeRequests > maxActiveRequests) {
      maxActiveRequests = activeRequests;
    }
    try {
      // 模拟网络耗时，便于观察并发
      await Future<void>.delayed(delay);

      if (path == '/bad.bin') {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        await request.response.close();
        return;
      }

      final content = contents[path];
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
      // 客户端取消等场景下，连接可能已关闭，这里只需保证 finally 清理计数
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

ProviderContainer _createContainer(Directory tempDir, {Folder? rootFolder}) {
  final container = ProviderContainer(overrides: [
    configFileProvider.overrideWithValue(
      JsonStorage(filePath: p.join(tempDir.path, 'config.json')),
    ),
    downloadPathProvider
        .overrideWith((ref) => p.join(tempDir.path, 'downloads')),
    sourceIdProvider.overrideWithValue('RJ00001'),
    titleProvider.overrideWithValue('测试作品'),
    cvLsProvider.overrideWithValue(const []),
    workInfoProvider.overrideWith((ref) async => {
          'title': '测试作品',
          'circle': {'name': ''},
          'vas': <Object>[],
          'tags': <Object>[],
          'release': '',
          'mainCoverUrl': '',
        }),
    worksIndexProvider.overrideWithValue(
      WorksIndex(filePath: p.join(tempDir.path, 'works_index.json')),
    ),
    if (rootFolder != null)
      rootFolderProvider.overrideWith((ref) => rootFolder),
  ]);
  addTearDown(container.dispose);
  return container;
}

Folder _rootWithFiles(List<String> paths, _TestServer server,
    {List<String>? badPaths}) {
  final root = Folder(id: 'RJ00001', title: 'RJ00001');
  for (final path in paths) {
    final isBad = badPaths?.contains(path) ?? false;
    root.children.add(FileAsset(
      id: path,
      type: 'audio',
      title: p.basename(path),
      mediaStreamUrl: server.url(path),
      mediaDownloadUrl: server.url(path),
      size: isBad ? 1 : server.content(path).length,
    )..selected = true);
  }
  return root;
}

void main() {
  test('并行时每文件线程数被压缩到总连接数上限内', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final manager = container.read(downloadManagerProvider);

    container.read(downloadThreadsProvider.notifier).state = 16;
    container.read(parallelDownloadCountProvider.notifier).state = 4;
    expect(manager.perFileThreadsForTesting(), 4);

    container.read(parallelDownloadCountProvider.notifier).state = 2;
    expect(manager.perFileThreadsForTesting(), 8);

    container.read(downloadThreadsProvider.notifier).state = 4;
    container.read(parallelDownloadCountProvider.notifier).state = 2;
    expect(manager.perFileThreadsForTesting(), 4);

    container.read(downloadThreadsProvider.notifier).state = 1;
    container.read(parallelDownloadCountProvider.notifier).state = 4;
    expect(manager.perFileThreadsForTesting(), 1);
  });

  test('并行下载：并发上限 2 且全部字节正确', () async {
    final server = await _TestServer.start(
      delay: const Duration(milliseconds: 150),
    );
    addTearDown(server.close);

    final tempDir =
        Directory.systemTemp.createTempSync('parallel_dl_test_concurrency');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final container = _createContainer(
      tempDir,
      rootFolder: _rootWithFiles(['/f1.bin', '/f2.bin', '/f3.bin'], server),
    );
    container.read(downloadThreadsProvider.notifier).state = 1;
    container.read(parallelDownloadCountProvider.notifier).state = 2;

    await container.read(downloadManagerProvider).run();

    expect(server.maxActiveRequests, lessThanOrEqualTo(2));
    expect(container.read(dlStatusProvider), DownloadStatus.completed);
    expect(container.read(currentDlNoProvider), 3);
    expect(container.read(processProvider), 1.0);

    for (final path in ['/f1.bin', '/f2.bin', '/f3.bin']) {
      final file = File(p.join(
        tempDir.path,
        'downloads',
        '测试作品',
        'RJ00001',
        p.basename(path),
      ));
      expect(await file.readAsBytes(), server.content(path));
    }
  });

  test('并行下载：单文件失败不阻塞其他文件，最终状态 failed', () async {
    final server = await _TestServer.start(
      delay: const Duration(milliseconds: 50),
    );
    addTearDown(server.close);

    final tempDir =
        Directory.systemTemp.createTempSync('parallel_dl_test_failed');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final container = _createContainer(
      tempDir,
      rootFolder: _rootWithFiles(
        ['/f1.bin', '/bad.bin', '/f2.bin'],
        server,
        badPaths: ['/bad.bin'],
      ),
    );
    container.read(downloadThreadsProvider.notifier).state = 1;
    container.read(parallelDownloadCountProvider.notifier).state = 2;

    await container.read(downloadManagerProvider).run();

    expect(container.read(dlStatusProvider), DownloadStatus.failed);
    expect(container.read(currentDlNoProvider), 2);

    for (final path in ['/f1.bin', '/f2.bin']) {
      final file = File(p.join(
        tempDir.path,
        'downloads',
        '测试作品',
        'RJ00001',
        p.basename(path),
      ));
      expect(await file.readAsBytes(), server.content(path));
    }
    expect(
      File(p.join(
        tempDir.path,
        'downloads',
        '测试作品',
        'RJ00001',
        'bad.bin',
      )).existsSync(),
      isFalse,
    );
  });

  test('并行下载：取消时所有在途请求中断且不生成最终文件', () async {
    final server = await _TestServer.start(
      delay: const Duration(seconds: 2),
    );
    addTearDown(server.close);

    final tempDir =
        Directory.systemTemp.createTempSync('parallel_dl_test_cancel');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final container = _createContainer(
      tempDir,
      rootFolder: _rootWithFiles(['/f1.bin', '/f2.bin', '/f3.bin'], server),
    );
    container.read(downloadThreadsProvider.notifier).state = 1;
    container.read(parallelDownloadCountProvider.notifier).state = 2;

    final runFuture = container.read(downloadManagerProvider).run();

    // 等待至少一个文件请求真正发出后再取消
    while (server.activeRequests == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    container.read(downloadManagerProvider).cancelAllDownload();
    await runFuture;

    expect(container.read(dlStatusProvider), DownloadStatus.canceled);
    // 服务端 handler 可能仍在 sleep，等待其自然结束
    while (server.activeRequests > 0) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(server.activeRequests, 0);

    for (final path in ['/f1.bin', '/f2.bin', '/f3.bin']) {
      expect(
        File(p.join(
          tempDir.path,
          'downloads',
          '测试作品',
          'RJ00001',
          p.basename(path),
        )).existsSync(),
        isFalse,
      );
    }
  });
}
