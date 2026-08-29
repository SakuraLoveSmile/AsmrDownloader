import 'dart:convert';
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
    this.etag,
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

  /// 所有响应附带（含 HEAD）；null 表示不发送 ETag。
  final String? etag;

  /// 注入式错误：状态码 → 剩余注入次数，优先于正常内容响应。
  final Map<int, int> failNext = {};

  final List<Map<String, String?>> requests = [];

  static Future<_TestServer> start({
    required Uint8List content,
    bool ignoreRange = false,
    bool ignoreRangeAfterProbe = false,
    bool cutSegment0Once = false,
    String? etag,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final testServer = _TestServer._(
      server,
      content,
      ignoreRange,
      ignoreRangeAfterProbe,
      cutSegment0Once,
      etag,
    );
    server.listen(testServer._handle);
    return testServer;
  }

  String get url => 'http://127.0.0.1:${server.port}/test.bin';

  void failNextTimes(int statusCode, int times) {
    failNext[statusCode] = (failNext[statusCode] ?? 0) + times;
  }

  void _applyCommonHeaders(HttpResponse response) {
    if (etag != null) {
      response.headers.set('etag', etag!);
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final range = request.headers.value('range');
    requests.add({'range': range, 'method': request.method});

    // HEAD 探测：只返回头（Content-Length / ETag），不写响应体
    if (request.method == 'HEAD') {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentLength = content.length;
      _applyCommonHeaders(request.response);
      await request.response.close();
      return;
    }

    // 注入式错误（404/503 等场景）
    final failEntry =
        failNext.entries.where((e) => e.value > 0).toList(growable: false);
    if (failEntry.isNotEmpty) {
      final status = failEntry.first.key;
      failNext[status] = status == failEntry.first.key
          ? failEntry.first.value - 1
          : failEntry.first.value;
      request.response.statusCode = status;
      await request.response.close();
      return;
    }

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
        _applyCommonHeaders(response);
        response.add(bytes.sublist(0, bytes.length ~/ 2));
        await response.close();
        return;
      }
      final response = request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.contentLength = bytes.length
        ..headers.set('content-range', 'bytes $start-$end/${content.length}');
      _applyCommonHeaders(response);
      response.add(bytes);
    } else {
      final response = request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentLength = content.length;
      _applyCommonHeaders(response);
      response.add(content);
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

/// 预写断点身份 manifest（模拟上一会话留下的断点）
Future<void> _writeManifest(
  String savePath,
  _TestServer server, {
  String? etag,
}) async {
  await File('$savePath.downloading.meta.json').writeAsString(json.encode({
    'url': server.url,
    'size': server.content.length,
    if (etag != null) 'etag': etag,
  }));
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
    await _writeManifest(savePath, server);

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
    await _writeManifest(savePath, server);

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

  test('大小未知：HEAD 探测大小后单线程下载成功', () async {
    final content = _makeContent(4096);
    final server = await _TestServer.start(content: content);
    addTearDown(server.close);

    final savePath = p.join(tempDir.path, 'unknown_size.bin');
    final ok = await downloader.download(
      url: server.url,
      savePath: savePath,
      fileSize: null,
      threadCount: 1,
    );

    expect(ok, isTrue);
    expect(await File(savePath).readAsBytes(), content);
    // HEAD 探测 1 次 + 单连接下载 1 次
    expect(server.requests, hasLength(2));
    expect(server.requests.first['method'], 'HEAD');
    expect(server.requests.last['range'], isNull);
  });

  test('永久错误 404：立即失败，不无限重试', () async {
    final content = _makeContent(4096);
    final server = await _TestServer.start(content: content);
    server.failNextTimes(404, 100);
    addTearDown(server.close);

    final savePath = p.join(tempDir.path, 'not_found.bin');
    final stopwatch = Stopwatch()..start();
    final ok = await downloader.download(
      url: server.url,
      savePath: savePath,
      fileSize: content.length,
      threadCount: 1,
    );
    stopwatch.stop();

    expect(ok, isFalse);
    // 永久错误不应重试：只发出 1 次请求且快速返回
    expect(server.requests, hasLength(1));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(File(savePath).existsSync(), isFalse);
  });

  test('临时错误 503：自动重试并在服务恢复后成功', () async {
    final content = _makeContent(4096);
    final server = await _TestServer.start(content: content);
    server.failNextTimes(503, 2);
    addTearDown(server.close);

    final savePath = p.join(tempDir.path, 'server_error.bin');
    final ok = await downloader.download(
      url: server.url,
      savePath: savePath,
      fileSize: content.length,
      threadCount: 1,
    );

    expect(ok, isTrue);
    expect(await File(savePath).readAsBytes(), content);
    // 两次 503 + 一次成功
    expect(server.requests, hasLength(3));
  });

  test('断点后服务器 ETag 改变：旧分段被丢弃，重新下载新内容', () async {
    const partSize = MultiThreadDownloader.minPartSize;
    final oldContent = _makeContent(partSize * 4);
    final newContent = _makeContent(partSize * 4);
    for (var i = 0; i < newContent.length; i++) {
      newContent[i] = (i * 7 + 3) % 251;
    }
    final server =
        await _TestServer.start(content: newContent, etag: 'new-etag');
    addTearDown(server.close);

    final savePath = p.join(tempDir.path, 'etag_changed.bin');
    // 模拟上一会话：part0 为旧内容，manifest 记录旧 ETag
    await File('$savePath.downloading')
        .writeAsBytes(oldContent.sublist(0, partSize));
    await _writeManifest(savePath, server, etag: 'old-etag');

    final ok = await downloader.download(
      url: server.url,
      savePath: savePath,
      fileSize: newContent.length,
      threadCount: 4,
    );

    expect(ok, isTrue);
    // 最终文件必须是新内容，而不是旧断点与新数据的拼接
    expect(await File(savePath).readAsBytes(), newContent);
  });

  test('最终文件长度与已知大小不符：不视为已完成，重新下载', () async {
    final content = _makeContent(4096);
    final server = await _TestServer.start(content: content);
    addTearDown(server.close);

    final savePath = p.join(tempDir.path, 'wrong_length.bin');
    // 残留的最终文件长度不符（如上次异常写入）
    await File(savePath).writeAsBytes([1, 2, 3]);

    final ok = await downloader.download(
      url: server.url,
      savePath: savePath,
      fileSize: content.length,
      threadCount: 1,
    );

    expect(ok, isTrue);
    expect(await File(savePath).readAsBytes(), content);
  });

  test('大小未知时最终文件已存在：不凭存在性直接宣告完成', () async {
    final content = _makeContent(4096);
    final server = await _TestServer.start(content: content);
    addTearDown(server.close);

    final savePath = p.join(tempDir.path, 'unknown_exists.bin');
    // 大小未知时无法验证残留文件的完整性：应重新下载覆盖
    await File(savePath).writeAsBytes([9, 9, 9]);

    final ok = await downloader.download(
      url: server.url,
      savePath: savePath,
      fileSize: null,
      threadCount: 1,
    );

    expect(ok, isTrue);
    expect(await File(savePath).readAsBytes(), content);
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
