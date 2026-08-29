import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:asmr_downloader/services/asmr_repo/asmr_api.dart';
import 'package:asmr_downloader/services/download/download_retry.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

enum _SegmentResult {
  completed,
  failed,
  canceled,
  rangeIgnored,
  identityChanged
}

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

/// 断点身份 manifest：记录断点文件对应的远端文件身份。
/// 恢复下载前比较，URL/大小/ETag/Last-Modified 明显改变时丢弃旧 part 从头下载。
class _DownloadManifest {
  _DownloadManifest({
    required this.url,
    this.size,
    this.etag,
    this.lastModified,
  });

  String url;
  int? size;
  String? etag;
  String? lastModified;

  Map<String, dynamic> toJson() => {
        'url': url,
        if (size != null) 'size': size,
        if (etag != null) 'etag': etag,
        if (lastModified != null) 'lastModified': lastModified,
      };

  static _DownloadManifest? fromJson(String raw) {
    try {
      final data = json.decode(raw) as Map<String, dynamic>;
      return _DownloadManifest(
        url: data['url']?.toString() ?? '',
        size: (data['size'] as num?)?.toInt(),
        etag: data['etag']?.toString(),
        lastModified: data['lastModified']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// 单文件多线程（多连接 Range 分段）下载器。
///
/// - 文件被切成若干段（每段至少 [minPartSize]），并发写入
///   `<savePath>.downloading`（第 0 段）与 `<savePath>.downloading.partN`；
/// - 每段独立断点续传：重启后按各 part 文件已有长度从对应 Range 继续；
/// - 全部分段完成后流式合并到 `<savePath>.downloading.merge`，校验长度后
///   原子改名；
/// - 服务器不支持 Range（探测非 206/缺 Content-Range）或探测失败时自动
///   回退单线程逻辑，完全兼容旧版 `.downloading` / `.downloading.part` 断点文件；
/// - 断点文件旁维护 `.downloading.meta.json` manifest（url/size/etag/
///   lastModified），远端文件更换时丢弃旧断点避免拼接错误数据；
/// - 网络失败按 [maxDownloadRetries] 有限重试（指数退避），永久性
///   HTTP 错误（404 等）立即失败。
///
/// [fileSize] 语义：null = 未知（先 HEAD 探测，仍未知则单连接下载到流结束）；
/// 0 = 真实空文件；>0 = 已知大小。
class MultiThreadDownloader {
  MultiThreadDownloader(
    this.api, {
    this.retryDelay = const Duration(seconds: 1),
  });

  final AsmrApi api;

  /// 重试的基础间隔（实际延迟按 1x/2x/4x/8x/16x 指数退避）
  final Duration retryDelay;

  /// 分段最小大小：避免给很小的文件开多个连接
  static const int minPartSize = 1024 * 1024;

  /// 断点身份失效后允许的重新下载次数上限（防止远端反复变更导致死循环）
  static const int _maxIdentityRestarts = 5;

  /// 多线程下载单个文件；返回 true 表示文件已完整下载且长度与已知大小一致。
  Future<bool> download({
    required String url,
    required String savePath,
    required int? fileSize,
    int threadCount = 4,
    CancelToken? cancelToken,
    void Function(int received, int total)? onProgress,
  }) async {
    final fileName = p.basename(savePath);
    final finalFile = File(savePath);

    // 最终文件已存在：已知大小时长度必须一致才直接完成；
    // 大小未知或长度不符的残留文件不可信，删除后重新下载。
    if (await finalFile.exists()) {
      final finalLen = await finalFile.length();
      if (fileSize != null && finalLen == fileSize) {
        await _cleanupWorkFiles(savePath);
        Log.info('file already downloaded: $fileName\nsavePath: $savePath');
        return true;
      }
      Log.warning('discard invalid final file: $fileName\n'
          'error: local length $finalLen, expected ${fileSize ?? 'unknown'}');
      await finalFile.delete();
    }

    // 真实空文件直接落盘
    if (fileSize == 0) {
      await finalFile.create(recursive: true);
      Log.info('download completed (empty file): $fileName');
      return true;
    }

    // 大小未知：先 HEAD 探测；探测不到则按单连接模式下载到流结束
    var size = fileSize;
    if (size == null) {
      size = await api.tryGetContentLength(url);
      if (size == 0) {
        await finalFile.create(recursive: true);
        Log.info('download completed (empty file): $fileName');
        return true;
      }
    }

    final maxUsefulThreads =
        math.max(1, ((size ?? 0) + minPartSize - 1) ~/ minPartSize);
    final effectiveThreads =
        math.min(math.max(1, threadCount), maxUsefulThreads);
    // 大小未知（探测不到）时无法规划分段，只能单连接下载到流结束
    if (size == null || effectiveThreads <= 1) {
      return _downloadSingle(
        url: url,
        savePath: savePath,
        size: size,
        manifest: _DownloadManifest(url: url, size: size),
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
        size: size,
        manifest: _DownloadManifest(url: url, size: size),
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
    }

    // 断点身份校验：残留分段存在时先验证 manifest，远端文件已更换则丢弃重来
    var manifest = await _prepareManifest(
      url: url,
      savePath: savePath,
      size: size,
      cancelToken: cancelToken,
    );

    var identityRestarts = 0;
    while (true) {
      final ok = await _downloadMulti(
        url: url,
        savePath: savePath,
        size: size,
        threadCount: effectiveThreads,
        manifest: manifest,
        cancelToken: cancelToken,
        onProgress: onProgress,
      );
      if (ok != _MultiOutcome.identityChanged) return ok == _MultiOutcome.done;
      identityRestarts++;
      if (identityRestarts > _maxIdentityRestarts) {
        Log.error('multi-thread download failed: $fileName\n'
            'error: remote file changed repeatedly '
            '($identityRestarts identity restarts)');
        return false;
      }
      manifest = _DownloadManifest(url: url, size: size);
      await _saveManifest(savePath, manifest);
    }
  }

  // ---------------------------------------------------------------- paths

  static String _downloadingPath(String savePath) => '$savePath.downloading';

  static String _mergePath(String savePath) => '$savePath.downloading.merge';

  static String _manifestPath(String savePath) =>
      '$savePath.downloading.meta.json';

  /// 旧版单线程续传使用的临时 chunk 路径（无数字后缀，区别于 .partN）
  static String _legacyTmpPath(String savePath) => '$savePath.downloading.part';

  static String _partPath(String savePath, int index) => index == 0
      ? _downloadingPath(savePath)
      : '${_downloadingPath(savePath)}.part$index';

  /// 是否存在任何断点工作文件（分段/单线程续传 chunk/合并临时文件）
  Future<bool> _hasWorkFiles(String savePath) async {
    for (final path in [
      _downloadingPath(savePath),
      _legacyTmpPath(savePath),
      _mergePath(savePath),
    ]) {
      if (await File(path).exists()) return true;
    }
    final dir = Directory(p.dirname(savePath));
    if (!await dir.exists()) return false;
    final prefix = '${p.basename(savePath)}.downloading.part';
    await for (final entity in dir.list()) {
      if (p.basename(entity.path).startsWith(prefix)) return true;
    }
    return false;
  }

  /// 清理某个最终文件对应的全部中间文件（分段、合并临时文件、旧版续传
  /// chunk、manifest）。
  Future<void> _cleanupWorkFiles(String savePath) async {
    final finalName = p.basename(savePath);
    final downloadPrefix = '$finalName.downloading';
    final dir = Directory(p.dirname(savePath));
    if (!await dir.exists()) return;

    await for (final entity in dir.list()) {
      final name = p.basename(entity.path);
      final isWorkFile = name == downloadPrefix ||
          name == '$downloadPrefix.merge' ||
          name == '$downloadPrefix.meta.json' ||
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

  // ------------------------------------------------------------ manifest

  /// 加载并校验断点 manifest；存在断点文件但身份不匹配时删除全部断点
  /// 并返回全新 manifest。身份校验项：url / size / （manifest 有记录时的）
  /// ETag / Last-Modified（后者通过一次 HEAD 探测远端当前值）。
  Future<_DownloadManifest> _prepareManifest({
    required String url,
    required String savePath,
    required int? size,
    CancelToken? cancelToken,
  }) async {
    final manifestFile = File(_manifestPath(savePath));
    _DownloadManifest? manifest;
    if (await manifestFile.exists()) {
      try {
        manifest =
            _DownloadManifest.fromJson(await manifestFile.readAsString());
      } catch (_) {
        manifest = null;
      }
    }

    if (await _hasWorkFiles(savePath)) {
      var mismatch = false;
      if (manifest == null) {
        // 无身份记录的残留断点：无法证明与当前远端文件同源，丢弃重下
        mismatch = true;
      } else {
        if (manifest.url != url) mismatch = true;
        if (!mismatch &&
            manifest.size != null &&
            size != null &&
            manifest.size != size) {
          mismatch = true;
        }
        if (!mismatch &&
            (manifest.etag != null || manifest.lastModified != null)) {
          final identity =
              await api.tryProbeRemoteIdentity(url, cancelToken: cancelToken);
          if (identity != null &&
              _identityMismatch(manifest, identity.contentLength, identity.etag,
                  identity.lastModified)) {
            mismatch = true;
          }
        }
      }
      if (mismatch) {
        Log.warning('discard stale download work files (remote identity '
            'changed): ${p.basename(savePath)}');
        await _cleanupWorkFiles(savePath);
      }
    }

    manifest ??= _DownloadManifest(url: url, size: size);
    await _saveManifest(savePath, manifest);
    return manifest;
  }

  bool _identityMismatch(_DownloadManifest manifest, int? size, String? etag,
      String? lastModified) {
    if (manifest.size != null && size != null && manifest.size != size) {
      return true;
    }
    if (manifest.etag != null && etag != null && manifest.etag != etag) {
      return true;
    }
    if (manifest.lastModified != null &&
        lastModified != null &&
        manifest.lastModified != lastModified) {
      return true;
    }
    return false;
  }

  Future<void> _saveManifest(
      String savePath, _DownloadManifest manifest) async {
    try {
      final file = File(_manifestPath(savePath));
      await file.parent.create(recursive: true);
      await file.writeAsString(json.encode(manifest.toJson()));
    } catch (e) {
      Log.warning('save download manifest failed: ${_manifestPath(savePath)}\n'
          'error: $e');
    }
  }

  /// 响应头身份校验：ETag/Last-Modified 与 manifest 记录不符时返回 true。
  /// 响应携带了 manifest 缺失的字段时顺带记录（持久化到 manifest）。
  Future<bool> _checkResponseIdentity({
    required _DownloadManifest manifest,
    required String savePath,
    required Response? response,
  }) async {
    if (response == null) return false;
    final etag = response.headers.value('etag');
    final lastModified = response.headers.value('last-modified');
    if (_identityMismatch(manifest, null, etag, lastModified)) {
      return true;
    }
    var updated = false;
    if (etag != null && manifest.etag == null) {
      manifest.etag = etag;
      updated = true;
    }
    if (lastModified != null && manifest.lastModified == null) {
      manifest.lastModified = lastModified;
      updated = true;
    }
    if (updated) await _saveManifest(savePath, manifest);
    return false;
  }

  /// 从 Content-Range 响应头解析总大小（`bytes 0-99/1234` → 1234）
  static int? _contentRangeTotal(String? contentRange) {
    if (contentRange == null) return null;
    final match = RegExp(r'/(\d+)$').firstMatch(contentRange.trim());
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
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

  /// 单线程断点续传（新文件不带 Range，续传使用开放 Range `bytes=N-`）。
  /// 大小未知（[size] == null）时以「请求正常结束」或 416 判定完成。
  Future<bool> _downloadSingle({
    required String url,
    required String savePath,
    required int? size,
    required _DownloadManifest manifest,
    CancelToken? cancelToken,
    void Function(int, int)? onProgress,
  }) async {
    final fileName = p.basename(savePath);
    final finalFile = File(savePath);
    final downloadingFile = File(_downloadingPath(savePath));
    final tmpFile = File(_legacyTmpPath(savePath));

    var attempts = 0;
    var lastProgressBytes = 0;
    var knownSize = size;

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
      if (knownSize != null && downloadedBytes > knownSize) {
        // 本地残留文件异常（比目标还大）：丢弃重下，避免死循环
        await downloadingFile.delete();
        downloadedBytes = 0;
      }

      if (await tmpFile.exists()) {
        final tmpLen = await tmpFile.length();
        if (tmpLen > 0 &&
            (knownSize == null || downloadedBytes + tmpLen <= knownSize)) {
          downloadedBytes += tmpLen;
          await _appendFile(downloadingFile, tmpFile);
        } else {
          await tmpFile.delete();
        }
      }

      if (knownSize != null && downloadedBytes == knownSize) {
        if (downloadedBytes == 0) {
          await finalFile.create(recursive: true);
        } else {
          await downloadingFile.rename(finalFile.path);
          if (await finalFile.length() != knownSize) {
            // 合并后长度与预期不符：不产生成功状态，丢弃重下
            Log.error('download failed: $fileName\n'
                'error: final length ${await finalFile.length()} '
                '!= expected $knownSize');
            await finalFile.delete();
            return false;
          }
        }
        Log.info('download completed: $fileName');
        return true;
      }

      // 重试预算：断点有进展则重置计数（持续无进展才消耗预算）
      if (downloadedBytes > lastProgressBytes) {
        attempts = 0;
        lastProgressBytes = downloadedBytes;
      }
      if (attempts > maxDownloadRetries) {
        Log.error('download failed: $fileName\n'
            'error: retry limit exceeded (no progress in $attempts retries)');
        return false;
      }

      try {
        if (downloadedBytes == 0) {
          Log.info('start downloading: $fileName\n'
              'fileSize: ${knownSize != null ? getSizeString(knownSize) : 'unknown'}\n'
              'url: $url\n'
              'savePath: $savePath');
          final response = await api.download(
            url,
            _downloadingPath(savePath),
            cancelToken: cancelToken,
            deleteOnError: false,
            onReceiveProgress: onProgress,
          );
          if (await _checkResponseIdentity(
            manifest: manifest,
            savePath: savePath,
            response: response,
          )) {
            await _cleanupWorkFiles(savePath);
            manifest = _DownloadManifest(url: url, size: knownSize);
            await _saveManifest(savePath, manifest);
            lastProgressBytes = 0;
            attempts = 0;
            continue;
          }
          if (knownSize == null) {
            // 大小未知：流正常结束即完整
            await downloadingFile.rename(finalFile.path);
            await _cleanupWorkFiles(savePath);
            Log.info('download completed: $fileName');
            return true;
          }
        } else {
          Log.info('resume downloading: $fileName\n'
              'downloadedSize: ${getSizeString(downloadedBytes)}, '
              'fileSize: ${knownSize != null ? getSizeString(knownSize) : 'unknown'}\n'
              'url: $url\n'
              'savePath: $savePath');
          final response = await api.download(
            url,
            _legacyTmpPath(savePath),
            cancelToken: cancelToken,
            deleteOnError: false,
            onReceiveProgress: (received, total) {
              onProgress?.call(received + downloadedBytes, knownSize ?? total);
            },
            options: Options(headers: {'range': 'bytes=$downloadedBytes-'}),
          );
          if (await _checkResponseIdentity(
            manifest: manifest,
            savePath: savePath,
            response: response,
          )) {
            await _cleanupWorkFiles(savePath);
            manifest = _DownloadManifest(url: url, size: knownSize);
            await _saveManifest(savePath, manifest);
            lastProgressBytes = 0;
            attempts = 0;
            continue;
          }
          if (response.statusCode == 200) {
            // 服务器忽略 Range：tmp 是完整文件，直接落位
            await _deleteIfExists(downloadingFile);
            await tmpFile.rename(downloadingFile.path);
            await downloadingFile.rename(finalFile.path);
            if (knownSize != null && await finalFile.length() != knownSize) {
              Log.error('download failed: $fileName\n'
                  'error: final length ${await finalFile.length()} '
                  '!= expected $knownSize');
              await finalFile.delete();
              return false;
            }
            await _cleanupWorkFiles(savePath);
            Log.info('download completed (range ignored): $fileName');
            return true;
          }
          // 尝试从 Content-Range 学习总大小（未知大小时）
          knownSize ??=
              _contentRangeTotal(response.headers.value('content-range'));
          await _appendFile(downloadingFile, tmpFile);
          if (knownSize == null) {
            // 干净结束的开放 Range 响应且无总大小信息：已到文件尾
            await downloadingFile.rename(finalFile.path);
            await _cleanupWorkFiles(savePath);
            Log.info('download completed: $fileName');
            return true;
          }
        }
        attempts = 0;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) {
          Log.warning('download canceled: $fileName\nerror: $e');
          return false;
        }
        // 即使请求中途失败也把已收到的 chunk 并回主文件，供下次续传
        await _appendFile(downloadingFile, tmpFile);
        if (e.response?.statusCode == 416) {
          if (knownSize == null) {
            // 大小未知时 416 = 本地断点已到文件尾：按完成处理
            await downloadingFile.rename(finalFile.path);
            await _cleanupWorkFiles(savePath);
            Log.info('download completed: $fileName');
            return true;
          }
          Log.error('download failed: $fileName\n'
              'statusCode = 416, range incorrect\n'
              'error: $e');
          return false;
        }
        if (isPermanentDownloadFailure(e)) {
          Log.error('download failed: $fileName\n'
              'statusCode = ${e.response?.statusCode} (permanent)\n'
              'error: $e');
          return false;
        }
        attempts++;
        Log.warning('download failed (attempt $attempts): $fileName\n'
            'error: $e');
        await Future.delayed(downloadRetryDelay(e, attempts, retryDelay));
      } catch (e) {
        Log.error('download failed: $fileName\nunhandled error: $e');
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

  Future<_MultiOutcome> _downloadMulti({
    required String url,
    required String savePath,
    required int size,
    required int threadCount,
    required _DownloadManifest manifest,
    CancelToken? cancelToken,
    void Function(int, int)? onProgress,
  }) async {
    final fileName = p.basename(savePath);

    // 上次合并一半留下的中间文件可以直接丢弃（各分段 part 都还在）
    await _deleteIfExists(File(_mergePath(savePath)));

    final segments = _planSegments(size, threadCount);

    // 旧版单线程续传 chunk：只在没有新分段残留时并回第 0 段
    final legacyTmp = File(_legacyTmpPath(savePath));
    final hasModernParts = await _hasModernPartFiles(savePath, segments.length);
    if (await legacyTmp.exists()) {
      if (!hasModernParts) {
        final part0 = File(_partPath(savePath, 0));
        final part0Len = await part0.exists() ? await part0.length() : 0;
        final legacyLen = await legacyTmp.length();
        if (legacyLen > 0 && part0Len + legacyLen <= size) {
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
      if (len == size && segment.size < size) {
        Log.info('multi-thread download resumed from a complete part: '
            '$fileName (part ${segment.index})');
        await partFile.rename(savePath);
        await _cleanupWorkFiles(savePath);
        return _MultiOutcome.done;
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
      return await _mergeSegments(segments, savePath, size)
          ? _MultiOutcome.done
          : _MultiOutcome.failed;
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
      return _MultiOutcome.canceled;
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
      return math.min(sum, size);
    }

    var lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
    void notifyProgress({bool force = false}) {
      final now = DateTime.now();
      if (!force &&
          now.difference(lastNotify) < const Duration(milliseconds: 100)) {
        return;
      }
      lastNotify = now;
      onProgress?.call(globalReceived(), size);
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
        'fileSize: ${getSizeString(size)}, threads: ${segments.length}\n'
        'url: $url\n'
        'savePath: $savePath');

    final results = await Future.wait([
      for (var i = 0; i < segments.length; i++)
        _runSegment(
          url: url,
          savePath: savePath,
          size: size,
          segment: segments[i],
          manifest: manifest,
          token: segmentTokens[i],
          notify: notifyProgress,
          onPermanentFailure: () => cancelOtherSegments(i),
          onRangeIgnored: () => cancelOtherSegments(i),
          onIdentityChanged: () => cancelOtherSegments(i),
        ),
    ]);

    if (cancelToken?.isCancelled == true) {
      Log.warning('multi-thread download canceled: $fileName');
      return _MultiOutcome.canceled;
    }

    if (results.contains(_SegmentResult.identityChanged)) {
      // 任一分段发现远端文件已更换：丢弃全部分段，由上层从头下载
      Log.warning('multi-thread download restart: remote file changed: '
          '$fileName');
      await _cleanupWorkFiles(savePath);
      return _MultiOutcome.identityChanged;
    }

    if (results.contains(_SegmentResult.rangeIgnored)) {
      // 服务器忽略了 Range：某个分段已经写入完整文件，直接采用它
      for (final segment in segments) {
        final partFile = File(_partPath(savePath, segment.index));
        if (await partFile.exists() && await partFile.length() == size) {
          await partFile.rename(savePath);
          await _cleanupWorkFiles(savePath);
          Log.info(
              'multi-thread download completed (range ignored): $fileName');
          return _MultiOutcome.done;
        }
      }
      // 理论上走不到：完整分段被并发写坏时清理后回退单线程
      await _cleanupWorkFiles(savePath);
      return await _downloadSingle(
        url: url,
        savePath: savePath,
        size: size,
        manifest: manifest,
        cancelToken: cancelToken,
        onProgress: onProgress,
      )
          ? _MultiOutcome.done
          : _MultiOutcome.failed;
    }

    if (results.contains(_SegmentResult.failed)) {
      Log.error('multi-thread download failed: $fileName\n'
          'error: some segment failed permanently');
      return _MultiOutcome.failed;
    }

    // 未被父 token 取消、也没有 rangeIgnored/failed，但出现 canceled：
    // 一般是内部异常取消，按取消处理（保留各分段供下次续传）。
    if (results.contains(_SegmentResult.canceled)) {
      Log.warning('multi-thread download canceled: $fileName');
      return _MultiOutcome.canceled;
    }

    return await _mergeSegments(segments, savePath, size)
        ? _MultiOutcome.done
        : _MultiOutcome.failed;
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
    required int size,
    required _Segment segment,
    required _DownloadManifest manifest,
    required CancelToken token,
    required void Function({bool force}) notify,
    required void Function() onPermanentFailure,
    required void Function() onRangeIgnored,
    required void Function() onIdentityChanged,
  }) async {
    final fileName = p.basename(savePath);
    final partPath = _partPath(savePath, segment.index);
    final partFile = File(partPath);
    await partFile.create(recursive: true);

    var attempts = 0;
    var lastProgressBytes = segment.completedBytes;

    while (true) {
      if (token.isCancelled) return _SegmentResult.canceled;

      final resumeFrom = math.min(segment.completedBytes, segment.size);
      segment.completedBytes = resumeFrom;
      if (resumeFrom >= segment.size) {
        segment.done = true;
        notify(force: true);
        return _SegmentResult.completed;
      }

      // 重试预算：断点有进展则重置计数
      if (resumeFrom > lastProgressBytes) {
        attempts = 0;
        lastProgressBytes = resumeFrom;
      }
      if (attempts > maxDownloadRetries) {
        Log.error('segment download failed: $fileName part ${segment.index}\n'
            'error: retry limit exceeded (no progress in $attempts retries)');
        onPermanentFailure();
        return _SegmentResult.failed;
      }

      final rangeStart = segment.start + resumeFrom;
      try {
        // dio 默认 FileMode.write 会先把已有 part 文件截断成 0，
        // 续传必须用 append：文件里已有 resumeFrom 字节 + 本次 range 响应
        // 正好补满一个分段
        final response = await api.download(
          url,
          partPath,
          cancelToken: token,
          deleteOnError: false,
          fileAccessMode: FileAccessMode.append,
          onReceiveProgress: (received, total) {
            segment.completedBytes = resumeFrom + received;
            notify();
          },
          options:
              Options(headers: {'range': 'bytes=$rangeStart-${segment.end}'}),
        );
        if (await _checkResponseIdentity(
          manifest: manifest,
          savePath: savePath,
          response: response,
        )) {
          onIdentityChanged();
          return _SegmentResult.identityChanged;
        }

        final len = await partFile.length();
        if (len >= segment.size) {
          if (len == size && segment.size < size) {
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
        attempts++;
        Log.warning('segment download ended early (attempt $attempts): '
            '$fileName part ${segment.index} ($len/${segment.size})');
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
        if (isPermanentDownloadFailure(e)) {
          Log.error('segment download failed: $fileName part ${segment.index}\n'
              'statusCode = ${e.response?.statusCode} (permanent)\n'
              'error: $e');
          onPermanentFailure();
          return _SegmentResult.failed;
        }
        attempts++;
        Log.warning('segment download failed (attempt $attempts): '
            '$fileName part ${segment.index}\n'
            'error: $e');
        await Future.delayed(downloadRetryDelay(e, attempts, retryDelay));
      } catch (e) {
        Log.error('segment download failed: $fileName part ${segment.index}\n'
            'unhandled error: $e');
        onPermanentFailure();
        return _SegmentResult.failed;
      }
    }
  }

  Future<bool> _mergeSegments(
      List<_Segment> segments, String savePath, int size) async {
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
      // 最终完整性校验：合并结果长度必须等于预期大小
      final mergedLen = await finalFile.length();
      if (mergedLen != size) {
        Log.error('merge segments failed: $fileName\n'
            'error: merged length $mergedLen != expected $size');
        await finalFile.delete();
        return false;
      }
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

/// _downloadMulti 的结果分类：identityChanged 表示远端文件已更换，
/// 需丢弃全部分段由上层重新发起。
enum _MultiOutcome { done, failed, canceled, identityChanged }
