import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:asmr_downloader/services/asmr_repo/asmr_api.dart';
import 'package:asmr_downloader/services/download/multi_thread_downloader.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _TestServer {
  _TestServer._(
    this.server,
    this.content,
    this.ignoreRange,
    this.ignoreRangeAfterProbe,
    this.cutSegment0Once,
  );

  final HttpServer server;
  final Uint8List content;
  final bool ignoreRange;

  /// 仅探测请求（bytes=0-0）返回 206，其余 Range 请求都忽略并返回完整文件。
  /// 用于模拟“探测通过但实际分段不支持 Range”的异常服务器。
  final bool ignoreRangeAfterProbe;

  /// 第一个分段 0 请求（bytes=0-…）只发一半字节后强行断开连接，
  /// 模拟下载中途网络中断；之后的请求正常服务。
  final bool cutSegment0Once;
  bool _cutDone = false;

  final List<Map<String, String?>> requests = [];

  static Future<_TestServer> start({
    required Uint8List content,
    bool ignoreRange = false,
    bool ignoreRangeAfterProbe = false,
    bool cutSegment0Once = false,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final testServer = _TestServer._(
      server,
      content,
      ignoreRange,
      ignoreRangeAfterProbe,
      cutSegment0Once,
    );
    server.listen(testServer._handle);
    return testServer;
  }

  String get url => 'http://127.0.0.1:${server.port}/test.bin';

  void _handle(HttpRequest request) async {
    final range = request.headers.value('range');
    requests.add({'range': range});

    final isProbe = range == 'bytes=0-0';
    if (!ignoreRange && !(ignoreRangeAfterProbe && !isProbe) && range != null) {
      final match = RegExp(r'^bytes=(\d+)-(\d+)?$').firstMatch(range);
      if (match == null) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        await request.response.close();
        return;
      }
      final start = int.parse(match.group(1)!);
      final endText = match.group(2);
      final end = endText == null || endText.isEmpty
          ? content.length - 1
          : math.min(int.parse(endText), content.length - 1);
      if (start >= content.length || start > end) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        await request.response.close();
        return;
      }
      final bytes = content.sublist(start, end + 1);
      if (cutSegment0Once && !_cutDone && !isProbe && start == 0) {
        _cutDone = true;
        // 故意不声明 Content-Length 并只发一半字节就结束响应，
        // 模拟下载中途断流：客户端收到比分段预期短的响应
        final response = request.response;
        response
          ..statusCode = HttpStatus.partialContent
          ..headers.set('content-range', 'bytes $start-$end/${content.length}');
        response.add(bytes.sublist(0, bytes.length ~/ 2));
        await response.close();
        return;
      }
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.contentLength = bytes.length
        ..headers.set('content-range', 'bytes $start-$end/${content.length}');
      request.response.add(bytes);
    } else {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentLength = content.length;
      request.response.add(content);
    }
    await request.response.close();
  }

  Future<void> close() => server.close(force: true);
}

Uint8List _makeContent(int size) {
  final bytes = Uint8List(size);
  for (var i = 0; i < size; i++) {
    bytes[i] = i % 251;
  }
  return bytes;
}

void main() {
  late Directory tempDir;
  late MultiThreadDownloader downloader;

  setUp(() {
    tempDir =
        Directory.systemTemp.createTempSync('multi_thread_downloader_test');
    downloader = MultiThreadDownloader(
      AsmrApi(),
      retryDelay: Duration.zero,
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('多线程分段下载：并发 Range 请求、字节正确、进度到 100%、清理 part', () async {
    const partSize = MultiThreadDownloader.minPartSize;
    final content = _makeContent(partSize * 4);
    final server = await _TestServer.start(content: content);
    addTearDown(server.close);

    final savePath = p.join(tempDir.path, 'multi.bin');
    var lastReceived = 0;
    var lastTotal = 0;
    final ok = await downloader.download(
      url: server.url,
      savePath: savePath,
      fileSize: content.length,
      threadCount: 4,
      onProgress: (received, total) {
        lastReceived = received;
        lastTotal = total;
      },
    );

    expect(ok, isTrue);
    expect(await File(savePath).readAsBytes(), content);
    expect(lastTotal, content.length);
    expect(lastReceived, content.length);

    // 第一个请求是 Range 探测（bytes=0-0），随后应有 4 个分段请求
    final rangeRequests =
        server.requests.where((request) => request['range'] != null).toList();
    expect(rangeRequests, hasLength(5));
    expect(rangeRequests.first['range'], 'bytes=0-0');

    final starts = <int>{
      for (final request in rangeRequests.skip(1))
        int.parse(
            RegExp(r'^bytes=(\d+)-').firstMatch(request['range']!)!.group(1)!),
    };
    expect(starts, {0, partSize, partSize * 2, partSize * 3});

    final files = tempDir.listSync().map((e) => p.basename(e.path)).toList();
    expect(files, ['multi.bin']);
  });

  test('分段断点续传：已有 part0/part1 时只续传剩余分段', () async {
    const partSize = MultiThreadDownloader.minPartSize;
    final content = _makeContent(partSize * 4);
    final server = await _TestServer.start(content: content);
    addTearDown(server.close);

    final savePath = p.join(tempDir.path, 'resume.bin');
    // 模拟上一次中断：前两个分段已经完整，后两个缺失
    await File('$savePath.downloading')
        .writeAsBytes(content.sublist(0, partSize));
    await File('$savePath.downloading.part1')
        .writeAsBytes(content.sublist(partSize, partSize * 2));

    final ok = await downloader.download(
      url: server.url,
      savePath: savePath,
      fileSize: content.length,
      threadCount: 4,
    );

    expect(ok, isTrue);
    expect(await File(savePath).readAsBytes(), content);

    // 探测 1 次 + 只请求缺失的 part2/part3
    final rangeRequests =
        server.requests.where((request) => request['range'] != null).toList();
    expect(rangeRequests, hasLength(3));
    final starts = <int>{
      for (final request in rangeRequests.skip(1))
        int.parse(
            RegExp(r'^bytes=(\d+)-').firstMatch(request['range']!)!.group(1)!),
    };
    expect(starts, {partSize * 2, partSize * 3});
  });

  test('服务器不支持 Range：自动回退单线程且字节正确', () async {
    const partSize = MultiThreadDownloader.minPartSize;
    final content = _makeContent(partSize * 2);
    final server = await _TestServer.start(content: content, ignoreRange: true);
    addTearDown(server.close);

    final savePath = p.join(tempDir.path, 'fallback.bin');
    final ok = await downloader.download(
      url: server.url,
      savePath: savePath,
      fileSize: content.length,
      threadCount: 4,
    );

    expect(ok, isTrue);
    expect(await File(savePath).readAsBytes(), content);

    // 探测请求带 Range 但服务器返回 200；真正的下载请求不应带 Range
    expect(server.requests, hasLength(2));
    expect(server.requests.first['range'], 'bytes=0-0');
    expect(server.requests.last['range'], isNull);
  });

  test('探测支持但分段请求忽略 Range：采用完整分段完成下载', () async {
    const partSize = MultiThreadDownloader.minPartSize;
    final content = _makeContent(partSize * 2);
    final server = await _TestServer.start(
      content: content,
      ignoreRangeAfterProbe: true,
    );
    addTearDown(server.close);

    final savePath = p.join(tempDir.path, 'range_ignored.bin');
    final ok = await downloader.download(
      url: server.url,
      savePath: savePath,
      fileSize: content.length,
      threadCount: 4,
    );

    expect(ok, isTrue);
    expect(await File(savePath).readAsBytes(), content);

    // 探测 1 次 + 两个分段请求（都返回了完整文件）
    final rangeRequests =
        server.requests.where((request) => request['range'] != null).toList();
    expect(rangeRequests, hasLength(3));
    expect(rangeRequests.first['range'], 'bytes=0-0');
  });

  test('部分下载的分段可续传完成（不再 100% 后倒退死循环）', () async {
    const partSize = MultiThreadDownloader.minPartSize;
    final content = _makeContent(partSize * 4);
    final server = await _TestServer.start(content: content);
    addTearDown(server.close);

    final savePath = p.join(tempDir.path, 'partial_part.bin');
    // 模拟上次中断：part0 只下了一半（0 < len < segment.size）。
    // dio.download 默认截断已有文件，若续传未用 append 会永远补不满该段
    await File('$savePath.downloading')
        .writeAsBytes(content.sublist(0, partSize ~/ 2));

    final ok = await downloader.download(
      url: server.url,
      savePath: savePath,
      fileSize: content.length,
      threadCount: 4,
    );

    expect(ok, isTrue);
    expect(await File(savePath).readAsBytes(), content);

    // 探测 1 次 + 4 个分段各 1 次；part0 从一半处续传而非从头重下
    final rangeRequests =
        server.requests.where((request) => request['range'] != null).toList();
    expect(rangeRequests, hasLength(5));
    final starts = <int>{
      for (final request in rangeRequests.skip(1))
        int.parse(
            RegExp(r'^bytes=(\d+)-').firstMatch(request['range']!)!.group(1)!),
    };
    expect(starts, {partSize ~/ 2, partSize, partSize * 2, partSize * 3});
  });

  test('分段中途断流后自动重试并续传完成', () async {
    const partSize = MultiThreadDownloader.minPartSize;
    final content = _makeContent(partSize * 4);
    final server = await _TestServer.start(
      content: content,
      cutSegment0Once: true,
    );
    addTearDown(server.close);

    final savePath = p.join(tempDir.path, 'cut.bin');
    final ok = await downloader.download(
      url: server.url,
      savePath: savePath,
      fileSize: content.length,
      threadCount: 4,
    );

    expect(ok, isTrue);
    expect(await File(savePath).readAsBytes(), content);

    // 探测 1 + 4 个分段 + 断连分段至少重试 1 次
    final rangeRequestCnt =
        server.requests.where((request) => request['range'] != null).length;
    expect(rangeRequestCnt, greaterThan(5));
  });

  test('空文件直接创建，不请求服务器', () async {
    final savePath = p.join(tempDir.path, 'empty.bin');
    final ok = await downloader.download(
      url: 'http://127.0.0.1:1/unused',
      savePath: savePath,
      fileSize: 0,
      threadCount: 4,
    );

    expect(ok, isTrue);
    expect(await File(savePath).exists(), isTrue);
    expect(await File(savePath).length(), 0);
  });

  test('最终文件已存在：直接完成并清理残留 part', () async {
    final content = _makeContent(1024);
    final savePath = p.join(tempDir.path, 'exists.bin');
    await File(savePath).writeAsBytes(content);
    // 模拟上次留下的残留
    await File('$savePath.downloading').writeAsBytes([1, 2, 3]);
    await File('$savePath.downloading.part1').writeAsBytes([4, 5, 6]);

    final ok = await downloader.download(
      url: 'http://127.0.0.1:1/unused',
      savePath: savePath,
      fileSize: content.length,
      threadCount: 4,
    );

    expect(ok, isTrue);
    expect(await File(savePath).readAsBytes(), content);
    expect(File('$savePath.downloading').existsSync(), isFalse);
    expect(File('$savePath.downloading.part1').existsSync(), isFalse);
  });

  test('取消后返回 false 且不生成最终文件', () async {
    const partSize = MultiThreadDownloader.minPartSize;
    final content = _makeContent(partSize * 4);
    final server = await _TestServer.start(content: content);
    addTearDown(server.close);

    final savePath = p.join(tempDir.path, 'cancel.bin');
    final token = CancelToken();
    token.cancel('测试取消');

    final ok = await downloader.download(
      url: server.url,
      savePath: savePath,
      fileSize: content.length,
      threadCount: 4,
      cancelToken: token,
    );

    expect(ok, isFalse);
    expect(File(savePath).existsSync(), isFalse);
  });
}
