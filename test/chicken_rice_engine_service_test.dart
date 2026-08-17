import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:asmr_downloader/services/download/chunk_downloader.dart';
import 'package:asmr_downloader/services/engine/chicken_rice_engine_service.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart' hide EnginePhase;
import 'package:path/path.dart' as p;

void main() {
  group('EngineManifest', () {
    test('fromJson 解析分卷清单（chunk 发现/hash/size）', () {
      final manifest = EngineManifest.fromJson({
        'name': 'rt.zip',
        'hash': 'ABCDEF0123456789',
        'size': 3514289663,
        'chunk_size': 2097152000,
        'chunks': ['rt.zip.0000', 'rt.zip.0001'],
      });
      expect(manifest.name, 'rt.zip');
      expect(manifest.hash, 'abcdef0123456789'); // 归一小写
      expect(manifest.size, 3514289663);
      expect(manifest.chunks, ['rt.zip.0000', 'rt.zip.0001']);
      // 最后一卷 = 总大小 - 前 n-1 卷
      expect(manifest.chunkLength(0), 2097152000);
      expect(manifest.chunkLength(1), 3514289663 - 2097152000);
    });

    test('单分卷时 chunkLength = 总大小', () {
      final manifest = EngineManifest.fromJson({
        'name': 'rt.zip',
        'hash': 'aa',
        'size': 1234,
        'chunk_size': 2000,
        'chunks': ['rt.zip.0000'],
      });
      expect(manifest.chunkLength(0), 1234);
    });
  });

  group('命名与 URL 构造', () {
    test('变体 → nomodel 资产基础名', () {
      expect(ChickenRiceEngineService.assetBaseName('cu128'),
          'faster_whisper_transwithai_windows_cu128-nomodel.zip');
      expect(ChickenRiceEngineService.assetBaseName('gfx110x_all'),
          'faster_whisper_transwithai_windows_gfx110x_all-nomodel.zip');
    });

    test('HF 文件直链：主源与 hf-mirror 回退', () {
      expect(
          ChickenRiceEngineService.hfFileUrl('a/b', 'model.bin'),
          'https://huggingface.co/a/b/resolve/main/model.bin');
      expect(
          ChickenRiceEngineService.hfFileUrl('a/b', 'model.bin', mirror: true),
          'https://hf-mirror.com/a/b/resolve/main/model.bin');
    });

    test('任务 → 主模型仓库映射', () {
      expect(ChickenRiceEngineService.mainModelRepo('translate'),
          contains('whisper-large-v2-translate-zh'));
      expect(ChickenRiceEngineService.mainModelRepo('transcribe'),
          contains('whisper-ja-1.5B-ct2'));
    });

    test('固定模型规格：VAD 改名落 models/ 根', () {
      final vad = ChickenRiceEngineService.fixedModelSpecs
          .where((s) => s.destRelPath == 'whisper_vad.onnx')
          .single;
      expect(vad.remoteName, 'model.onnx');
      expect(
          ChickenRiceEngineService.fixedModelSpecs
              .any((s) => s.destRelPath.startsWith('whisper-base/')),
          isTrue);
    });
  });

  group('probe 安装状态探测', () {
    test('未配置/空目录 → 未安装', () async {
      final svc = ChickenRiceEngineService();
      expect((await svc.probe(null)).installed, isFalse);
      expect((await svc.probe('')).installed, isFalse);
      final tmp = Directory.systemTemp.createTempSync('eng_probe_empty');
      expect((await svc.probe(tmp.path)).installed, isFalse);
      tmp.deleteSync(recursive: true);
    });

    test('infer.exe + VAD + 主模型 → 已安装且模型完整', () async {
      final tmp = Directory.systemTemp.createTempSync('eng_probe_ok');
      final exeDir = Directory(p.join(tmp.path, 'rt'))..createSync();
      File(p.join(exeDir.path, 'infer.exe')).writeAsStringSync('x');
      final models = Directory(p.join(exeDir.path, 'models'))..createSync();
      File(p.join(models.path, 'whisper_vad.onnx')).writeAsStringSync('v');
      File(p.join(models.path, 'model.bin')).writeAsStringSync('m');

      final svc = ChickenRiceEngineService();
      final result = await svc.probe(tmp.path);
      expect(result.installed, isTrue);
      expect(result.exePath, p.join(exeDir.path, 'infer.exe'));
      expect(result.hasVad, isTrue);
      expect(result.hasMainModel, isTrue);
      expect(result.modelsReady, isTrue);
      tmp.deleteSync(recursive: true);
    });

    test('只有 infer.exe → 已安装但模型缺失', () async {
      final tmp = Directory.systemTemp.createTempSync('eng_probe_nomodel');
      File(p.join(tmp.path, 'infer.exe')).writeAsStringSync('x');
      final svc = ChickenRiceEngineService();
      final result = await svc.probe(tmp.path);
      expect(result.installed, isTrue);
      expect(result.modelsReady, isFalse);
      tmp.deleteSync(recursive: true);
    });
  });

  group('install 安装流程', () {
    /// 构造一个真实的（很小的）zip：内含 rt/infer.exe
    List<int> buildFakeZip() {
      final archive = Archive();
      final content = Uint8List.fromList(utf8.encode('fake exe'));
      archive.addFile(
          ArchiveFile('rt/infer.exe', content.length, content));
      return ZipEncoder().encode(archive)!;
    }

    ChickenRiceEngineService buildService({
      required List<int> zipBytes,
      required int Function() freeSpace,
    }) {
      final hash = sha256.convert(zipBytes).toString();
      final manifestJson = json.encode({
        'name': 'rt.zip',
        'hash': hash,
        'size': zipBytes.length,
        'chunk_size': zipBytes.length,
        'chunks': ['rt.zip.0000'],
      });
      final releaseJson = json.encode({
        'tag_name': 'vTEST',
        'assets': [
          {
            'name':
                '${ChickenRiceEngineService.assetBaseName('cu128')}.manifest',
            'browser_download_url':
                'https://fake.test/${ChickenRiceEngineService.assetBaseName('cu128')}.manifest',
          }
        ],
      });
      final apiDio = Dio()
        ..httpClientAdapter = _FakeAdapter({
          'api.github.com': releaseJson,
          '.manifest': manifestJson,
          'huggingface.co/api': '[]',
        });
      return ChickenRiceEngineService(
        downloader: _FakeDownloader(zipBytes),
        apiDio: apiDio,
        freeSpaceBytes: (dir) async => freeSpace(),
      );
    }

    test('磁盘空间不足 → 立即失败不下载', () async {
      final svc = buildService(zipBytes: buildFakeZip(), freeSpace: () => 10);
      final states = <EngineInstallState>[];
      final tmp = Directory.systemTemp.createTempSync('eng_inst_nospace');
      final exe = await svc.install(
        installDir: tmp.path,
        variant: 'cu128',
        task: 'translate',
        onState: states.add,
      );
      expect(exe, isNull);
      final failed = states.lastWhere((s) => s.phase == EnginePhase.failed);
      expect(failed.message, contains('磁盘空间不足'));
      tmp.deleteSync(recursive: true);
    });

    test('端到端：分卷下载→合并校验→解压→模型→返回 exe 路径', () async {
      final zipBytes = buildFakeZip();
      final svc = buildService(zipBytes: zipBytes, freeSpace: () => 1 << 62);
      final states = <EngineInstallState>[];
      final tmp = Directory.systemTemp.createTempSync('eng_inst_ok');
      final exe = await svc.install(
        installDir: tmp.path,
        variant: 'cu128',
        task: 'translate',
        onState: states.add,
      );
      // 解压产物中定位 infer.exe（zip 带顶层目录 rt/）
      expect(exe, p.join(tmp.path, 'rt', 'infer.exe'));
      // 状态机关键阶段都经过
      final phases = states.map((s) => s.phase).toSet();
      expect(phases, containsAll([
        EnginePhase.fetchingRelease,
        EnginePhase.downloading,
        EnginePhase.merging,
        EnginePhase.extracting,
        EnginePhase.downloadingModels,
        EnginePhase.done,
      ]));
      // 模型文件落到 exe 同级 models/（fake 下载器写入）
      final modelsDir = Directory(p.join(tmp.path, 'rt', 'models'));
      expect(File(p.join(modelsDir.path, 'whisper_vad.onnx')).existsSync(),
          isTrue);
      expect(File(p.join(modelsDir.path, 'model.bin')).existsSync(), isTrue);
      // 分卷临时目录已清理
      expect(Directory(p.join(tmp.path, '.asmr_engine_dl')).existsSync(),
          isFalse);
      // probe 复核：已安装且模型完整
      final probe = await svc.probe(tmp.path);
      expect(probe.installed, isTrue);
      expect(probe.modelsReady, isTrue);
      tmp.deleteSync(recursive: true);
    });

    test('manifest 校验失败（hash 不符）→ failed 且删除合并文件', () async {
      final zipBytes = buildFakeZip();
      final svc = buildService(zipBytes: zipBytes, freeSpace: () => 1 << 62);
      // 篡改 manifest hash：直接构造一个坏服务
      final badRelease = json.encode({
        'tag_name': 'vTEST',
        'assets': [
          {
            'name':
                '${ChickenRiceEngineService.assetBaseName('cu128')}.manifest',
            'browser_download_url':
                'https://fake.test/${ChickenRiceEngineService.assetBaseName('cu128')}.manifest',
          }
        ],
      });
      final badManifest = json.encode({
        'name': 'rt.zip',
        'hash': 'deadbeef',
        'size': zipBytes.length,
        'chunk_size': zipBytes.length,
        'chunks': ['rt.zip.0000'],
      });
      final badSvc = ChickenRiceEngineService(
        downloader: _FakeDownloader(zipBytes),
        apiDio: Dio()
          ..httpClientAdapter = _FakeAdapter({
            'api.github.com': badRelease,
            '.manifest': badManifest,
            'huggingface.co/api': '[]',
          }),
        freeSpaceBytes: (dir) async => 1 << 62,
      );
      final states = <EngineInstallState>[];
      final tmp = Directory.systemTemp.createTempSync('eng_inst_badhash');
      final exe = await badSvc.install(
        installDir: tmp.path,
        variant: 'cu128',
        task: 'translate',
        onState: states.add,
      );
      expect(exe, isNull);
      final failed = states.lastWhere((s) => s.phase == EnginePhase.failed);
      expect(failed.message, contains('完整性校验失败'));
      // 损坏的合并 zip 已被删除
      final zipFile = File(p.join(tmp.path, '.asmr_engine_dl', 'rt.zip'));
      expect(zipFile.existsSync(), isFalse);
      tmp.deleteSync(recursive: true);
      // 引用原服务避免未使用告警
      expect(svc, isNotNull);
    });

    test('API 清单缺 model.bin → 兜底合并后仍会下载', () async {
      final zipBytes = buildFakeZip();
      final hash = sha256.convert(zipBytes).toString();
      final manifestJson = json.encode({
        'name': 'rt.zip',
        'hash': hash,
        'size': zipBytes.length,
        'chunk_size': zipBytes.length,
        'chunks': ['rt.zip.0000'],
      });
      final releaseJson = json.encode({
        'tag_name': 'vTEST',
        'assets': [
          {
            'name':
                '${ChickenRiceEngineService.assetBaseName('cu128')}.manifest',
            'browser_download_url':
                'https://fake.test/${ChickenRiceEngineService.assetBaseName('cu128')}.manifest',
          }
        ],
      });
      // tree API 只返回 config.json（模拟清单异常缺项）
      final treeJson = json.encode([
        {'type': 'file', 'path': 'config.json', 'size': 100},
      ]);
      final downloader = _FakeDownloader(zipBytes);
      final svc = ChickenRiceEngineService(
        downloader: downloader,
        apiDio: Dio()
          ..httpClientAdapter = _FakeAdapter({
            'api.github.com': releaseJson,
            '.manifest': manifestJson,
            'tree/main': treeJson,
          }),
        freeSpaceBytes: (dir) async => 1 << 62,
      );
      final tmp = Directory.systemTemp.createTempSync('eng_inst_nobinlist');
      final exe = await svc.install(
        installDir: tmp.path,
        variant: 'cu128',
        task: 'translate',
        onState: (_) {},
      );
      expect(exe, isNotNull);
      // model.bin 被兜底合并进清单并实际下载
      expect(downloader.downloadedUrls.any((u) => u.endsWith('/model.bin')),
          isTrue);
      expect(
          File(p.join(tmp.path, 'rt', 'models', 'model.bin')).existsSync(),
          isTrue);
      tmp.deleteSync(recursive: true);
    });

    test('model.bin 下载失败/缺失 → 安装不得假成功', () async {
      final zipBytes = buildFakeZip();
      final hash = sha256.convert(zipBytes).toString();
      final manifestJson = json.encode({
        'name': 'rt.zip',
        'hash': hash,
        'size': zipBytes.length,
        'chunk_size': zipBytes.length,
        'chunks': ['rt.zip.0000'],
      });
      final releaseJson = json.encode({
        'tag_name': 'vTEST',
        'assets': [
          {
            'name':
                '${ChickenRiceEngineService.assetBaseName('cu128')}.manifest',
            'browser_download_url':
                'https://fake.test/${ChickenRiceEngineService.assetBaseName('cu128')}.manifest',
          }
        ],
      });
      // 假下载器：model.bin 直接失败（主源+镜像都失败）
      final downloader = _FakeDownloader(zipBytes, failPaths: ['model.bin']);
      final svc = ChickenRiceEngineService(
        downloader: downloader,
        apiDio: Dio()
          ..httpClientAdapter = _FakeAdapter({
            'api.github.com': releaseJson,
            '.manifest': manifestJson,
            'huggingface.co/api': '[]',
          }),
        freeSpaceBytes: (dir) async => 1 << 62,
      );
      final states = <EngineInstallState>[];
      final tmp = Directory.systemTemp.createTempSync('eng_inst_binfail');
      final exe = await svc.install(
        installDir: tmp.path,
        variant: 'cu128',
        task: 'translate',
        onState: states.add,
      );
      expect(exe, isNull);
      expect(states.any((s) => s.phase == EnginePhase.failed), isTrue);
      expect(states.any((s) => s.phase == EnginePhase.done), isFalse);
      tmp.deleteSync(recursive: true);
    });

    test('Token 无效（401）→ 自动降级匿名重试成功', () async {
      final zipBytes = buildFakeZip();
      final hash = sha256.convert(zipBytes).toString();
      final releaseJson = json.encode({
        'tag_name': 'vTEST',
        'assets': [
          {
            'name':
                '${ChickenRiceEngineService.assetBaseName('cu128')}.manifest',
            'browser_download_url':
                'https://fake.test/${ChickenRiceEngineService.assetBaseName('cu128')}.manifest',
          }
        ],
      });
      final manifestJson = json.encode({
        'name': 'rt.zip',
        'hash': hash,
        'size': zipBytes.length,
        'chunk_size': zipBytes.length,
        'chunks': ['rt.zip.0000'],
      });
      // 第一次请求 401（带无效 token），随后匿名重试/后续请求均 200；
      // 401 body 与真实 GitHub 一致为合法 JSON（dio 5.8 默认
      // receiveDataWhenStatusError 会对错误响应做 JSON 解码）
      final adapter = _SequenceAdapter([
        ResponseBody.fromString('{"message":"Bad credentials"}', 401),
        ResponseBody.fromString(releaseJson, 200),
        ResponseBody.fromString(manifestJson, 200),
        ResponseBody.fromString('[]', 200),
      ]);
      final svc = ChickenRiceEngineService(
        downloader: _FakeDownloader(zipBytes),
        apiDio: Dio()..httpClientAdapter = adapter,
        freeSpaceBytes: (dir) async => 1 << 62,
      );
      svc.githubToken = 'ghp_invalid';
      final tmp = Directory.systemTemp.createTempSync('eng_401_retry');
      final exe = await svc.install(
        installDir: tmp.path,
        variant: 'cu128',
        task: 'translate',
        onState: (_) {},
      );
      expect(exe, isNotNull);
      // 第一次带无效 token，匿名重试起不再携带
      expect(adapter.headersList[0]['authorization'], 'Bearer ghp_invalid');
      expect(adapter.headersList[1].containsKey('authorization'), isFalse);
      tmp.deleteSync(recursive: true);
    });

    test('获取 Release 撞 403 限流 → 失败提示速率限制（非网络/代理）', () async {
      final svc = ChickenRiceEngineService(
        downloader: _FakeDownloader(buildFakeZip()),
        apiDio: Dio()
          ..httpClientAdapter = _FakeAdapter({'api.github.com': '{}'},
              statusOverride: 403,
              responseHeaders: {'x-ratelimit-remaining': '0'}),
        freeSpaceBytes: (dir) async => 1 << 62,
      );
      final states = <EngineInstallState>[];
      final tmp = Directory.systemTemp.createTempSync('eng_rl_403');
      final exe = await svc.install(
        installDir: tmp.path,
        variant: 'cu128',
        task: 'translate',
        onState: states.add,
      );
      expect(exe, isNull);
      final failed = states.lastWhere((s) => s.phase == EnginePhase.failed);
      expect(failed.error, contains('速率限制'));
      tmp.deleteSync(recursive: true);
    });

    test('获取 Release 阶段取消 → 判定为已取消而非「安装失败」', () async {
      final svc = buildService(
          zipBytes: buildFakeZip(), freeSpace: () => 1 << 62);
      final states = <EngineInstallState>[];
      final tmp = Directory.systemTemp.createTempSync('eng_cancel_fetch');
      final exe = await svc.install(
        installDir: tmp.path,
        variant: 'cu128',
        task: 'translate',
        onState: (s) {
          states.add(s);
          // 模拟用户在获取 Release 信息时点「取消安装」
          if (s.phase == EnginePhase.fetchingRelease) svc.requestCancel();
        },
      );
      expect(exe, isNull);
      expect(states.last.phase, EnginePhase.canceled);
      // 用户主动取消不应误报为安装失败
      expect(states.any((s) => s.phase == EnginePhase.failed), isFalse);
      tmp.deleteSync(recursive: true);
    });

    test('解压阶段取消 → 终止 tar 并判定为已取消（不继续模型下载）', () async {
      final svc = buildService(
          zipBytes: buildFakeZip(), freeSpace: () => 1 << 62);
      final states = <EngineInstallState>[];
      final tmp = Directory.systemTemp.createTempSync('eng_cancel_extract');
      final exe = await svc.install(
        installDir: tmp.path,
        variant: 'cu128',
        task: 'translate',
        onState: (s) {
          states.add(s);
          // 模拟用户在解压阶段点「取消安装」
          if (s.phase == EnginePhase.extracting) svc.requestCancel();
        },
      );
      expect(exe, isNull);
      expect(states.last.phase, EnginePhase.canceled);
      // 取消后不得继续走模型下载/伪完成
      expect(states.any((s) => s.phase == EnginePhase.downloadingModels),
          isFalse);
      expect(states.any((s) => s.phase == EnginePhase.done), isFalse);
      tmp.deleteSync(recursive: true);
    });

    test('模型下载阶段取消 → 判定为已取消', () async {
      final svc = buildService(
          zipBytes: buildFakeZip(), freeSpace: () => 1 << 62);
      final states = <EngineInstallState>[];
      final tmp = Directory.systemTemp.createTempSync('eng_cancel_models');
      final exe = await svc.install(
        installDir: tmp.path,
        variant: 'cu128',
        task: 'translate',
        onState: (s) {
          states.add(s);
          // 模拟用户在模型下载阶段点「取消安装」
          if (s.phase == EnginePhase.downloadingModels) svc.requestCancel();
        },
      );
      expect(exe, isNull);
      expect(states.last.phase, EnginePhase.canceled);
      expect(states.any((s) => s.phase == EnginePhase.done), isFalse);
      tmp.deleteSync(recursive: true);
    });
  });
}

/// 按 URL 关键字返回预置响应的假 Dio 适配器。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responses,
      {this.statusOverride, this.responseHeaders});

  /// key = URL 包含的子串，value = 响应体
  final Map<String, String> responses;

  /// 非 null 时强制返回该状态码（模拟 403 限流等）
  final int? statusOverride;

  /// 附加响应头（如 x-ratelimit-remaining）
  final Map<String, String>? responseHeaders;

  @override
  void close({bool force = true}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    // 与真实 dio 一致：token 已取消的请求直接抛 cancel 异常
    final token = options.cancelToken;
    if (token != null && token.isCancelled) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
        error: token.cancelError,
      );
    }
    final url = options.uri.toString();
    for (final entry in responses.entries) {
      if (url.contains(entry.key)) {
        return ResponseBody.fromString(entry.value, statusOverride ?? 200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
              for (final h in responseHeaders?.entries ??
                  const <MapEntry<String, String>>[])
                h.key: [h.value],
            });
      }
    }
    return ResponseBody.fromString('not found', 404);
  }
}

/// 按顺序返回预置响应的适配器（记录每次请求头，供认证降级断言）。
class _SequenceAdapter implements HttpClientAdapter {
  _SequenceAdapter(this.responses);

  final List<ResponseBody> responses;
  final List<Map<String, String>> headersList = [];
  final List<String> urls = [];
  var _index = 0;

  @override
  void close({bool force = true}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    headersList.add({
      for (final e in options.headers.entries)
        e.key.toLowerCase(): '${e.value}',
    });
    urls.add(options.uri.toString());
    final resp =
        responses[_index < responses.length ? _index : responses.length - 1];
    _index++;
    // 与真实 GitHub API 一致：JSON 响应带 content-type
    resp.headers[Headers.contentTypeHeader] = [Headers.jsonContentType];
    return resp;
  }
}

/// 假下载器：分卷直接写入预置 zip 字节，模型文件写入占位内容。
class _FakeDownloader extends ChunkDownloader {
  _FakeDownloader(this.zipBytes, {this.failPaths = const []});

  final List<int> zipBytes;

  /// savePath 命中其中任一子串时模拟下载失败
  final List<String> failPaths;
  final downloadedUrls = <String>[];

  @override
  Future<bool> download({
    required String url,
    required String savePath,
    int fileSize = 0,
    int threadCount = 4,
    CancelToken? cancelToken,
    void Function(int received, int total)? onProgress,
  }) async {
    downloadedUrls.add(url);
    if (failPaths.any((s) => savePath.contains(s))) return false;
    final f = File(savePath)..createSync(recursive: true);
    if (savePath.contains('.asmr_engine_dl')) {
      f.writeAsBytesSync(zipBytes);
    } else {
      f.writeAsStringSync('m');
    }
    final size = fileSize > 0 ? fileSize : 1;
    onProgress?.call(size, size);
    return true;
  }
}
