import 'dart:io';
import 'dart:math' as math;

import 'package:asmr_downloader/services/asmr_repo/asmr_api.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

enum _SegmentResult { completed, failed, canceled, rangeIgnored }

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

/// 单文件多线程（多连接 Range 分段）下载器。
///
/// - 文件被切成若干段（每段至少 [minPartSize]），并发写入
///   `<savePath>.downloading`（第 0 段）与 `<savePath>.downloading.partN`；
/// - 每段独立断点续传：重启后按各 part 文件已有长度从对应 Range 继续；
/// - 全部分段完成后流式合并到 `<savePath>.downloading.merge`，再原子改名；
/// - 服务器不支持 Range（探测非 206）或探测失败时自动回退单线程逻辑，
///   完全兼容旧版 `.downloading` / `.downloading.part` 断点文件。
class MultiThreadDownloader {
  MultiThreadDownloader(
    this.api, {
    this.retryDelay = const Duration(seconds: 3),
  });

  final AsmrApi api;

  /// 单段网络失败后的重试间隔（无限重试，取消才停止）
  final Duration retryDelay;

  /// 分段最小大小：避免给很小的文件开多个连接
  static const int minPartSize = 1024 * 1024;

  /// 多线程下载单个文件；返回 true 表示文件已完整下载。
  Future<bool> download({
    required String url,
    required String savePath,
    required int fileSize,
    int threadCount = 4,
    CancelToken? cancelToken,
    void Function(int received, int total)? onProgress,
  }) async {
    final fileName = p.basename(savePath);
    final finalFile = File(savePath);

    // 最终文件已存在：清理历史分段残留后直接完成
    if (await finalFile.exists()) {
      await _cleanupWorkFiles(savePath);
      Log.info('file already downloaded: $fileName\nsavePath: $savePath');
      return true;
    }

    // 空文件直接落盘
    if (fileSize <= 0) {
      await finalFile.create(recursive: true);
      Log.info('download completed (empty file): $fileName');
      return true;
    }

    final maxUsefulThreads =
        math.max(1, (fileSize + minPartSize - 1) ~/ minPartSize);
    final effectiveThreads =
        math.min(math.max(1, threadCount), maxUsefulThreads);
    if (effectiveThreads <= 1) {
      return _downloadSingle(
        url: url,
        savePath: savePath,
        fileSize: fileSize,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
    }

    // 多线程依赖 Range；探测失败/不支持时回退单线程，保证任何服务器都能下载
    final rangeSupported =
        await api.supportsRangeDownload(url, cancelToken: cancelToken);
    if (rangeSupported != true) {
      Log.warning('multi-thread download fallback to single thread: $fileName\n'
          'error: server does not support range');
      return _downloadSingle(
        url: url,
        savePath: savePath,
        fileSize: fileSize,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
    }

    return _downloadMulti(
      url: url,
      savePath: savePath,
      fileSize: fileSize,
      threadCount: effectiveThreads,
      cancelToken: cancelToken,
      onProgress: onProgress,
    );
  }

  // ---------------------------------------------------------------- paths

  static String _downloadingPath(String savePath) => '$savePath.downloading';

  static String _mergePath(String savePath) => '$savePath.downloading.merge';

  /// 旧版单线程续传使用的临时 chunk 路径（无数字后缀，区别于 .partN）
  static String _legacyTmpPath(String savePath) => '$savePath.downloading.part';

  static String _partPath(String savePath, int index) => index == 0
      ? _downloadingPath(savePath)
      : '${_downloadingPath(savePath)}.part$index';

  /// 清理某个最终文件对应的全部中间文件（分段、合并临时文件、旧版续传 chunk）。
  Future<void> _cleanupWorkFiles(String savePath) async {
    final finalName = p.basename(savePath);
    final downloadPrefix = '$finalName.downloading';
    final dir = Directory(p.dirname(savePath));
    if (!await dir.exists()) return;

    await for (final entity in dir.list()) {
      final name = p.basename(entity.path);
      final isWorkFile = name == downloadPrefix ||
          name == '$downloadPrefix.merge' ||
          name.startsWith('$downloadPrefix.part');
      if (isWorkFile) {
        try {
          await File(entity.path).delete();
        } catch (e) {
          Log.warning('cleanup download work file failed: ${entity.path}\n'
              'error: $e');
        }
      }
    }
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// 流式把 source 追加到 target 末尾并删除 source（避免整块 readAsBytes）。
  Future<void> _appendFile(File target, File source) async {
    if (!await source.exists()) return;
    final sink = target.openWrite(mode: FileMode.append);
    try {
      await sink.addStream(source.openRead());
    } finally {
      await sink.close();
    }
    await source.delete();
  }

  // ------------------------------------------------------------- single

  /// 单线程断点续传（与历史行为一致：新文件不带 Range，续传才带 Range）。
  Future<bool> _downloadSingle({
    required String url,
    required String savePath,
    required int fileSize,
    CancelToken? cancelToken,
    void Function(int, int)? onProgress,
  }) async {
    final fileName = p.basename(savePath);
    final finalFile = File(savePath);
    final downloadingFile = File(_downloadingPath(savePath));
    final tmpFile = File(_legacyTmpPath(savePath));

    while (true) {
      if (cancelToken?.isCancelled == true) {
        Log.warning('download canceled: $fileName');
        return false;
      }

      if (await finalFile.exists()) {
        await _cleanupWorkFiles(savePath);
        return true;
      }

      var downloadedBytes = 0;
      if (await downloadingFile.exists()) {
        downloadedBytes = await downloadingFile.length();
      }
      if (downloadedBytes > fileSize) {
        // 本地残留文件异常（比目标还大）：丢弃重下，避免死循环
        await downloadingFile.delete();
        downloadedBytes = 0;
      }

      if (await tmpFile.exists()) {
        final tmpLen = await tmpFile.length();
        if (tmpLen > 0 && downloadedBytes + tmpLen <= fileSize) {
          downloadedBytes += tmpLen;
          await _appendFile(downloadingFile, tmpFile);
        } else {
          await tmpFile.delete();
        }
      }

      if (downloadedBytes < fileSize) {
        try {
          if (downloadedBytes == 0) {
            Log.info('start downloading: $fileName\n'
                'fileSize: ${getSizeString(fileSize)}\n'
                'url: $url\n'
                'savePath: $savePath');
            await api.download(
              url,
              _downloadingPath(savePath),
              cancelToken: cancelToken,
              deleteOnError: false,
              onReceiveProgress: onProgress,
            );
          } else {
            Log.info('resume downloading: $fileName\n'
                'downloadedSize: ${getSizeString(downloadedBytes)}, '
                'fileSize: ${getSizeString(fileSize)}\n'
                'url: $url\n'
                'savePath: $savePath');
            await api.download(
              url,
              _legacyTmpPath(savePath),
              cancelToken: cancelToken,
              deleteOnError: false,
              onReceiveProgress: (received, total) {
                onProgress?.call(received + downloadedBytes, fileSize);
              },
              options: Options(
                  headers: {'range': 'bytes=$downloadedBytes-$fileSize'}),
            );
          }
        } on DioException catch (e) {
          if (e.type == DioExceptionType.cancel) {
            Log.warning('download canceled: $fileName\nerror: $e');
            return false;
          }
          if (e.response?.statusCode == 416) {
            Log.error('download failed: $fileName\n'
                'statusCode = 416, range incorrect\n'
                'error: $e');
            return false;
          }
          Log.warning('download failed: $fileName\nerror: $e');
          await Future.delayed(retryDelay);
        } catch (e) {
          Log.error('download failed: $fileName\nunhandled error: $e');
          return false;
        } finally {
          // 即使请求中途失败也把已收到的 chunk 并回主文件，供下次续传
          await _appendFile(downloadingFile, tmpFile);
        }
      } else if (downloadedBytes == fileSize) {
        if (downloadedBytes == 0) {
          await finalFile.create(recursive: true);
        } else {
          await downloadingFile.rename(finalFile.path);
        }
        Log.info('download completed: $fileName');
        return true;
      } else {
        Log.error('download failed: $fileName\n'
            'error: downloadedBytes > fileSize');
        return false;
      }
    }
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
      segments.add(_Segment(
        index: i,
        start: cursor,
        end: cursor + size - 1,
      ));
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

    // 上次合并一半留下的中间文件可以直接丢弃（各分段 part 都还在）
    await _deleteIfExists(File(_mergePath(savePath)));

    final segments = _planSegments(fileSize, threadCount);

    // 旧版单线程续传 chunk：只在没有新分段残留时并回第 0 段
    final legacyTmp = File(_legacyTmpPath(savePath));
    final hasModernParts =
        await _hasModernPartFiles(savePath, segments.length);
    if (await legacyTmp.exists()) {
      if (!hasModernParts) {
        final part0 = File(_partPath(savePath, 0));
        final part0Len = await part0.exists() ? await part0.length() : 0;
        final legacyLen = await legacyTmp.length();
        if (legacyLen > 0 && part0Len + legacyLen <= fileSize) {
          await _appendFile(part0, legacyTmp);
        } else {
          await legacyTmp.delete();
        }
      } else {
        await legacyTmp.delete();
      }
    }

    // 扫描各分段本地进度；处理「服务器忽略 Range 导致某分段已含完整文件」的残留
    for (final segment in segments) {
      final partFile = File(_partPath(savePath, segment.index));
      if (!await partFile.exists()) continue;
      final len = await partFile.length();
      if (len == fileSize && segment.size < fileSize) {
        Log.info('multi-thread download resumed from a complete part: '
            '$fileName (part ${segment.index})');
        await partFile.rename(savePath);
        await _cleanupWorkFiles(savePath);
        return true;
      }
      if (len > segment.size) {
        Log.warning('discard oversized part file: '
            '$fileName part ${segment.index} ($len > ${segment.size})');
        await partFile.delete();
      } else if (len == segment.size) {
        segment.completedBytes = segment.size;
        segment.done = true;
      } else {
        segment.completedBytes = len;
      }
    }

    if (segments.every((segment) => segment.done)) {
      return _mergeSegments(segments, savePath);
    }

    // 每个分段使用独立 CancelToken；父 token 取消时联动取消所有分段
    final segmentTokens = List<CancelToken>.generate(
      segments.length,
      (_) => CancelToken(),
    );
    if (cancelToken?.isCancelled == true) {
      for (final token in segmentTokens) {
        token.cancel('下载已取消');
      }
      Log.warning('download canceled: $fileName');
      return false;
    }
    cancelToken?.whenCancel.then((_) {
      for (final token in segmentTokens) {
        if (!token.isCancelled) {
          token.cancel('下载已取消');
        }
      }
    });

    int globalReceived() {
      var sum = 0;
      for (final segment in segments) {
        sum += math.min(segment.completedBytes, segment.size);
      }
      return math.min(sum, fileSize);
    }

    var lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
    void notifyProgress({bool force = false}) {
      final now = DateTime.now();
      if (!force &&
          now.difference(lastNotify) <
              const Duration(milliseconds: 100)) {
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
    Log.info('start multi-thread downloading: $fileName\n'
        'fileSize: ${getSizeString(fileSize)}, threads: ${segments.length}\n'
        'url: $url\n'
        'savePath: $savePath');

    final results = await Future.wait([
      for (var i = 0; i < segments.length; i++)
        _runSegment(
          url: url,
          savePath: savePath,
          fileSize: fileSize,
          segment: segments[i],
          token: segmentTokens[i],
          notify: notifyProgress,
          onPermanentFailure: () => cancelOtherSegments(i),
          onRangeIgnored: () => cancelOtherSegments(i),
        ),
    ]);

    if (cancelToken?.isCancelled == true) {
      Log.warning('multi-thread download canceled: $fileName');
      return false;
    }

    if (results.contains(_SegmentResult.rangeIgnored)) {
      // 服务器忽略了 Range：某个分段已经写入完整文件，直接采用它
      for (final segment in segments) {
        final partFile = File(_partPath(savePath, segment.index));
        if (await partFile.exists() &&
            await partFile.length() == fileSize) {
          await partFile.rename(savePath);
          await _cleanupWorkFiles(savePath);
          Log.info(
              'multi-thread download completed (range ignored): $fileName');
          return true;
        }
      }
      // 理论上走不到：完整分段被并发写坏时清理后回退单线程
      await _cleanupWorkFiles(savePath);
      return _downloadSingle(
        url: url,
        savePath: savePath,
        fileSize: fileSize,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
    }

    if (results.contains(_SegmentResult.failed)) {
      Log.error('multi-thread download failed: $fileName\n'
          'error: some segment failed permanently');
      return false;
    }

    // 未被父 token 取消、也没有 rangeIgnored/failed，但出现 canceled：
    // 一般是内部异常取消，按取消处理（保留各分段供下次续传）。
    if (results.contains(_SegmentResult.canceled)) {
      Log.warning('multi-thread download canceled: $fileName');
      return false;
    }

    return _mergeSegments(segments, savePath);
  }

  Future<bool> _hasModernPartFiles(String savePath, int segmentCount) async {
    for (var i = 1; i < segmentCount; i++) {
      if (await File(_partPath(savePath, i)).exists()) return true;
    }
    return false;
  }

  Future<_SegmentResult> _runSegment({
    required String url,
    required String savePath,
    required int fileSize,
    required _Segment segment,
    required CancelToken token,
    required void Function({bool force}) notify,
    required void Function() onPermanentFailure,
    required void Function() onRangeIgnored,
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
        // dio 默认 FileMode.write 会先把已有 part 文件截断成 0，
        // 续传必须用 append：文件里已有 resumeFrom 字节 + 本次 range 响应
        // 正好补满一个分段
        await api.download(
          url,
          partPath,
          cancelToken: token,
          deleteOnError: false,
          fileAccessMode: FileAccessMode.append,
          onReceiveProgress: (received, total) {
            segment.completedBytes = resumeFrom + received;
            notify();
          },
          options: Options(
              headers: {'range': 'bytes=$rangeStart-${segment.end}'}),
        );

        final len = await partFile.length();
        if (len >= segment.size) {
          if (len == fileSize && segment.size < fileSize) {
            // 服务器忽略了 Range：该分段被写成了完整文件
            onRangeIgnored();
            return _SegmentResult.rangeIgnored;
          }
          if (len > segment.size) {
            // 超长但又不是完整文件：服务端行为异常，丢弃避免错误续传
            Log.error('segment download failed: '
                '$fileName part ${segment.index}\n'
                'error: part size $len exceeds segment size ${segment.size}');
            await partFile.delete();
            onPermanentFailure();
            return _SegmentResult.failed;
          }
          segment.completedBytes = segment.size;
          segment.done = true;
          notify(force: true);
          return _SegmentResult.completed;
        }

        // 响应提前结束且未抛错（少见）：保留已下部分，稍后继续
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
          Log.error('segment download failed: $fileName part ${segment.index}\n'
              'statusCode = 416, range incorrect\n'
              'error: $e');
          onPermanentFailure();
          return _SegmentResult.failed;
        }
        Log.warning('segment download failed: $fileName part ${segment.index}\n'
            'error: $e');
        await Future.delayed(retryDelay);
      } catch (e) {
        Log.error('segment download failed: $fileName part ${segment.index}\n'
            'unhandled error: $e');
        onPermanentFailure();
        return _SegmentResult.failed;
      }
    }
  }

  Future<bool> _mergeSegments(List<_Segment> segments, String savePath) async {
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
      Log.info('download completed (multi-thread): $fileName');
      return true;
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      await _deleteIfExists(mergeFile);
      Log.error('merge segments failed: $fileName\nerror: $e');
      return false;
    }
  }
}
