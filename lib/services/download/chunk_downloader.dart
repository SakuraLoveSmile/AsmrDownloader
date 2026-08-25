import 'dart:io';
import 'dart:math' as math;

import 'package:asmr_downloader/utils/log.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:path/path.dart' as p;

enum _SegmentResult { completed, failed, canceled }

class _Segment {
  _Segment({required this.index, required this.start, required this.end});

  final int index;

  /// 该分段在完整文件中的起始偏移（含）
  final int start;

  /// 该分段在完整文件中的结束偏移（含）
  final int end;

  /// 该分段的 part 文件中已下载的字节数
  int completedBytes = 0;
  bool done = false;

  int get size => end - start + 1;
}

/// 通用单文件分段断点续传下载器（纯 dio，不耦合业务 API）。
///
/// 与 MultiThreadDownloader 同构但独立：用于 AI 翻译引擎安装时从
/// GitHub Release / HuggingFace 下载大文件。
///
/// - 文件被切成若干段（每段至少 [minPartSize]），并发写入
///   `<savePath>.cdl.part0..partN`；
/// - 每段独立断点续传：按各 part 文件已有长度从对应 Range 继续；
/// - 全部分段完成后流式合并为 `<savePath>.cdl.merge`，再原子改名；
/// - 服务器不支持 Range（探测非 206）时回退单连接顺序下载。
class ChunkDownloader {
  ChunkDownloader({Dio? dio, this.retryDelay = const Duration(seconds: 3)})
      : _dio = dio ?? Dio() {
    _dio.options
      ..connectTimeout = const Duration(seconds: 15)
      ..receiveTimeout = const Duration(minutes: 10);
  }

  final Dio _dio;

  /// 单段网络失败后的重试间隔（无限重试，取消才停止）
  final Duration retryDelay;

  /// 分段最小大小：避免为很小的文件开多个连接
  static const int minPartSize = 4 * 1024 * 1024;

  /// 应用代理（与 AsmrApi.proxy 同语义，如 'PROXY 127.0.0.1:7897; DIRECT'）
  set proxy(String proxy) {
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (uri) => proxy;
        return client;
      },
    );
  }

  /// 下载单个文件；返回 true 表示文件已完整落盘 [savePath]。
  /// [fileSize] <= 0 时先 HEAD/GET 探测获取。
  Future<bool> download({
    required String url,
    required String savePath,
    int fileSize = 0,
    int threadCount = 4,
    CancelToken? cancelToken,
    void Function(int received, int total)? onProgress,
  }) async {
    final fileName = p.basename(savePath);
    final finalFile = File(savePath);
    if (await finalFile.exists()) {
      if (fileSize <= 0 || await finalFile.length() == fileSize) {
        await _cleanupWorkFiles(savePath);
        Log.info('chunk download: already exists: $fileName');
        return true;
      }
      // 大小不符（残留）：删除重下
      await finalFile.delete();
    }

    var size = fileSize;
    if (size <= 0) {
      size = await _probeSize(url, cancelToken);
      if (size <= 0) {
        Log.error('chunk download failed: $fileName\n'
            'error: cannot determine file size');
        return false;
      }
    }
    await File(savePath).parent.create(recursive: true);

    final rangeSupported =
        await _supportsRange(url, cancelToken: cancelToken) == true;
    if (!rangeSupported) {
      Log.warning('chunk download fallback to single stream: $fileName');
      return _downloadSingle(
        url: url,
        savePath: savePath,
        fileSize: size,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
    }

    return _downloadMulti(
      url: url,
      savePath: savePath,
      fileSize: size,
      threadCount: threadCount,
      cancelToken: cancelToken,
      onProgress: onProgress,
    );
  }

  // ------------------------------------------------------------- probes

  Future<int> _probeSize(String url, CancelToken? cancelToken) async {
    try {
      final resp = await _dio.head(url,
          cancelToken: cancelToken, options: Options(followRedirects: true));
      final len = resp.headers.value(Headers.contentLengthHeader);
      return int.tryParse(len ?? '') ?? 0;
    } catch (e) {
      Log.warning('chunk download probe size failed: $url\nerror: $e');
      return 0;
    }
  }

  Future<bool?> _supportsRange(String url, {CancelToken? cancelToken}) async {
    try {
      final response = await _dio.get(
        url,
        options: Options(
          headers: {'range': 'bytes=0-0'},
          responseType: ResponseType.stream,
          followRedirects: true,
        ),
        cancelToken: cancelToken,
      );
      // 及时释放连接
      await (response.data as ResponseBody).stream.drain<void>();
      return response.statusCode == 206;
    } catch (e) {
      Log.warning('chunk download range probe failed: $url\nerror: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------- paths

  static String _partPath(String savePath, int index) =>
      '$savePath.cdl.part$index';

  static String _mergePath(String savePath) => '$savePath.cdl.merge';

  static String _singleTmpPath(String savePath) => '$savePath.cdl.tmp';

  /// 清理某个最终文件对应的全部中间文件。
  Future<void> _cleanupWorkFiles(String savePath) async {
    final finalName = p.basename(savePath);
    final prefix = '$finalName.cdl';
    final dir = Directory(p.dirname(savePath));
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      final name = p.basename(entity.path);
      if (name.startsWith(prefix)) {
        try {
          await File(entity.path).delete();
        } catch (e) {
          Log.warning('cleanup chunk work file failed: ${entity.path}\n'
              'error: $e');
        }
      }
    }
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }

  // ------------------------------------------------------------- single

  /// 单连接顺序下载（不支持 Range 的服务器），支持断点续传。
  Future<bool> _downloadSingle({
    required String url,
    required String savePath,
    required int fileSize,
    CancelToken? cancelToken,
    void Function(int, int)? onProgress,
  }) async {
    final fileName = p.basename(savePath);
    final tmpFile = File(_singleTmpPath(savePath));

    while (true) {
      if (cancelToken?.isCancelled == true) {
        Log.warning('chunk download canceled: $fileName');
        return false;
      }
      var downloadedBytes = await tmpFile.exists() ? await tmpFile.length() : 0;
      if (downloadedBytes > fileSize) {
        await tmpFile.delete();
        downloadedBytes = 0;
      }
      if (downloadedBytes >= fileSize) break;

      try {
        await _dio.download(
          url,
          tmpFile.path,
          cancelToken: cancelToken,
          deleteOnError: false,
          // dio 默认 FileMode.write 会先截断已有 tmp 文件；续传要求追加
          fileAccessMode: FileAccessMode.append,
          options: downloadedBytes > 0
              ? Options(headers: {'range': 'bytes=$downloadedBytes-'})
              : null,
          onReceiveProgress: (received, total) {
            onProgress?.call(downloadedBytes + received, fileSize);
          },
        );
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) {
          Log.warning('chunk download canceled: $fileName');
          return false;
        }
        Log.warning('chunk download failed: $fileName\nerror: $e');
        await Future.delayed(retryDelay);
      } catch (e) {
        Log.error('chunk download failed: $fileName\nunhandled error: $e');
        return false;
      }
    }

    final len = await tmpFile.exists() ? await tmpFile.length() : 0;
    if (len < fileSize) {
      Log.error('chunk download failed: $fileName\n'
          'error: incomplete after loop ($len/$fileSize)');
      return false;
    }
    await tmpFile.rename(savePath);
    await _cleanupWorkFiles(savePath);
    Log.info('chunk download completed: $fileName');
    return true;
  }

  // -------------------------------------------------------------- multi

  List<_Segment> _planSegments(int fileSize, int threadCount) {
    final count = math.min(
      threadCount,
      math.max(1, (fileSize + minPartSize - 1) ~/ minPartSize),
    );
    final baseSize = fileSize ~/ count;
    final remainder = fileSize % count;

    final segments = <_Segment>[];
    var cursor = 0;
    for (var i = 0; i < count; i++) {
      final size = baseSize + (i < remainder ? 1 : 0);
      if (size <= 0) break;
      segments.add(_Segment(index: i, start: cursor, end: cursor + size - 1));
      cursor += size;
    }
    return segments;
  }

  Future<bool> _downloadMulti({
    required String url,
    required String savePath,
    required int fileSize,
    required int threadCount,
    CancelToken? cancelToken,
    void Function(int, int)? onProgress,
  }) async {
    final fileName = p.basename(savePath);
    await _deleteIfExists(File(_mergePath(savePath)));
    await _deleteIfExists(File(_singleTmpPath(savePath)));

    final segments = _planSegments(fileSize, threadCount);

    // 扫描各分段本地进度
    for (final segment in segments) {
      final partFile = File(_partPath(savePath, segment.index));
      if (!await partFile.exists()) continue;
      final len = await partFile.length();
      if (len > segment.size) {
        Log.warning('discard oversized chunk part: '
            '$fileName part ${segment.index} ($len > ${segment.size})');
        await partFile.delete();
      } else if (len == segment.size) {
        segment.completedBytes = segment.size;
        segment.done = true;
      } else {
        segment.completedBytes = len;
      }
    }

    if (segments.every((s) => s.done)) {
      return _mergeSegments(segments, savePath, fileSize);
    }

    // 每个分段独立 CancelToken；父 token 取消时联动
    final segmentTokens =
        List<CancelToken>.generate(segments.length, (_) => CancelToken());
    if (cancelToken?.isCancelled == true) {
      for (final t in segmentTokens) {
        t.cancel('下载已取消');
      }
      return false;
    }
    cancelToken?.whenCancel.then((_) {
      for (final t in segmentTokens) {
        if (!t.isCancelled) t.cancel('下载已取消');
      }
    });

    int globalReceived() {
      var sum = 0;
      for (final s in segments) {
        sum += math.min(s.completedBytes, s.size);
      }
      return math.min(sum, fileSize);
    }

    var lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
    void notifyProgress({bool force = false}) {
      final now = DateTime.now();
      if (!force &&
          now.difference(lastNotify) < const Duration(milliseconds: 100)) {
        return;
      }
      lastNotify = now;
      onProgress?.call(globalReceived(), fileSize);
    }

    void cancelOtherSegments(int currentIndex) {
      for (var i = 0; i < segmentTokens.length; i++) {
        if (i != currentIndex && !segmentTokens[i].isCancelled) {
          segmentTokens[i].cancel('分段下载终止');
        }
      }
    }

    notifyProgress();
    Log.info('start chunk downloading: $fileName\n'
        'fileSize: $fileSize, segments: ${segments.length}\n'
        'url: $url\nsavePath: $savePath');

    final results = await Future.wait([
      for (var i = 0; i < segments.length; i++)
        _runSegment(
          url: url,
          savePath: savePath,
          segment: segments[i],
          token: segmentTokens[i],
          notify: notifyProgress,
          onPermanentFailure: () => cancelOtherSegments(i),
        ),
    ]);

    if (cancelToken?.isCancelled == true) {
      Log.warning('chunk download canceled: $fileName');
      return false;
    }
    if (results.contains(_SegmentResult.failed)) {
      Log.error('chunk download failed: $fileName\n'
          'error: some segment failed permanently');
      return false;
    }
    if (results.contains(_SegmentResult.canceled)) {
      Log.warning('chunk download canceled: $fileName');
      return false;
    }
    return _mergeSegments(segments, savePath, fileSize);
  }

  Future<_SegmentResult> _runSegment({
    required String url,
    required String savePath,
    required _Segment segment,
    required CancelToken token,
    required void Function({bool force}) notify,
    required void Function() onPermanentFailure,
  }) async {
    final fileName = p.basename(savePath);
    final partPath = _partPath(savePath, segment.index);
    final partFile = File(partPath);
    await partFile.create(recursive: true);

    while (true) {
      if (token.isCancelled) return _SegmentResult.canceled;

      final resumeFrom = math.min(segment.completedBytes, segment.size);
      segment.completedBytes = resumeFrom;
      if (resumeFrom >= segment.size) {
        segment.done = true;
        notify(force: true);
        return _SegmentResult.completed;
      }

      final rangeStart = segment.start + resumeFrom;
      try {
        // 与 MultiThreadDownloader 相同：dio 默认截断已有文件，续传须 append
        await _dio.download(
          url,
          partPath,
          cancelToken: token,
          deleteOnError: false,
          fileAccessMode: FileAccessMode.append,
          options:
              Options(headers: {'range': 'bytes=$rangeStart-${segment.end}'}),
          onReceiveProgress: (received, total) {
            segment.completedBytes = resumeFrom + received;
            notify();
          },
        );

        final len = await partFile.length();
        if (len >= segment.size) {
          if (len > segment.size) {
            Log.error('segment download failed: '
                '$fileName part ${segment.index}\n'
                'error: part size $len exceeds ${segment.size}');
            await partFile.delete();
            onPermanentFailure();
            return _SegmentResult.failed;
          }
          segment.completedBytes = segment.size;
          segment.done = true;
          notify(force: true);
          return _SegmentResult.completed;
        }
        // 响应提前结束且未抛错：保留已下部分，稍后继续
        segment.completedBytes = len;
        await Future.delayed(retryDelay);
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) return _SegmentResult.canceled;
        if (e.response?.statusCode == 416) {
          final len = await partFile.length();
          if (len >= segment.size) {
            segment.completedBytes = segment.size;
            segment.done = true;
            notify(force: true);
            return _SegmentResult.completed;
          }
          Log.error('segment download failed: $fileName part '
              '${segment.index}\nstatusCode = 416\nerror: $e');
          onPermanentFailure();
          return _SegmentResult.failed;
        }
        Log.warning('segment download failed: $fileName part '
            '${segment.index}\nerror: $e');
        await Future.delayed(retryDelay);
      } catch (e) {
        Log.error('segment download failed: $fileName part '
            '${segment.index}\nunhandled error: $e');
        onPermanentFailure();
        return _SegmentResult.failed;
      }
    }
  }

  Future<bool> _mergeSegments(
      List<_Segment> segments, String savePath, int fileSize) async {
    final fileName = p.basename(savePath);
    final finalFile = File(savePath);
    if (await finalFile.exists()) {
      await _cleanupWorkFiles(savePath);
      return true;
    }

    final mergeFile = File(_mergePath(savePath));
    await _deleteIfExists(mergeFile);
    final sink = mergeFile.openWrite();
    try {
      for (final segment in segments) {
        final partFile = File(_partPath(savePath, segment.index));
        if (!await partFile.exists()) {
          throw StateError('part ${segment.index} missing');
        }
        final len = await partFile.length();
        if (len < segment.size) {
          throw StateError(
              'part ${segment.index} incomplete: $len/${segment.size}');
        }
        await sink.addStream(partFile.openRead());
      }
      await sink.close();
      await mergeFile.rename(savePath);
      await _cleanupWorkFiles(savePath);
      Log.info('chunk download completed (merged): $fileName');
      return true;
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      await _deleteIfExists(mergeFile);
      Log.error('merge chunk segments failed: $fileName\nerror: $e');
      return false;
    }
  }
}
