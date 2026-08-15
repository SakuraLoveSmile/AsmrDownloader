import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:asmr_downloader/services/download/chunk_downloader.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:path/path.dart' as p;

/// 引擎安装阶段。
enum EnginePhase {
  idle,
  fetchingRelease,
  downloading,
  merging,
  verifying,
  extracting,
  downloadingModels,
  configuring,
  done,
  failed,
  canceled,
}

/// 安装状态快照（UI 展示用）。
class EngineInstallState {
  final EnginePhase phase;
  final String message;

  /// 当前步骤序号（第几个分卷/模型文件，从 1 起）
  final int stepIndex;
  final int stepCount;

  /// 当前步骤已接收/总量（字节）
  final int received;
  final int total;
  final String? error;

  const EngineInstallState({
    this.phase = EnginePhase.idle,
    this.message = '',
    this.stepIndex = 0,
    this.stepCount = 0,
    this.received = 0,
    this.total = 0,
    this.error,
  });

  static const idle = EngineInstallState();

  bool get busy =>
      phase != EnginePhase.idle &&
      phase != EnginePhase.done &&
      phase != EnginePhase.failed &&
      phase != EnginePhase.canceled;

  /// 当前步骤进度（0~1）
  double get fraction => total <= 0 ? 0.0 : (received / total).clamp(0.0, 1.0);

  EngineInstallState copyWith({
    EnginePhase? phase,
    String? message,
    int? stepIndex,
    int? stepCount,
    int? received,
    int? total,
    String? error,
  }) {
    return EngineInstallState(
      phase: phase ?? this.phase,
      message: message ?? this.message,
      stepIndex: stepIndex ?? this.stepIndex,
      stepCount: stepCount ?? this.stepCount,
      received: received ?? this.received,
      total: total ?? this.total,
      error: error,
    );
  }
}

/// 上游 Release 的分卷清单（`.zip.manifest`）。
class EngineManifest {
  final String name;

  /// 合并后 zip 的 SHA-256（小写十六进制）
  final String hash;
  final int size;
  final int chunkSize;
  final List<String> chunks;

  const EngineManifest({
    required this.name,
    required this.hash,
    required this.size,
    required this.chunkSize,
    required this.chunks,
  });

  static EngineManifest fromJson(Map<String, dynamic> json) {
    return EngineManifest(
      name: json['name'] as String? ?? '',
      hash: (json['hash'] as String? ?? '').toLowerCase(),
      size: json['size'] as int? ?? 0,
      chunkSize: json['chunk_size'] as int? ?? 0,
      chunks: (json['chunks'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  /// 第 [index] 个分卷的大小（最后一卷 = 总大小 - 前 n-1 卷）
  int chunkLength(int index) {
    if (index == chunks.length - 1) {
      return size - chunkSize * (chunks.length - 1);
    }
    return chunkSize;
  }
}

/// 可安装的上游变体（NVIDIA CUDA / AMD ROCm；上游无纯 CPU 包）。
class EngineVariant {
  final String id;
  final String label;
  final String description;
  final bool isAmd;

  const EngineVariant({
    required this.id,
    required this.label,
    required this.description,
    required this.isAmd,
  });

  static const List<EngineVariant> all = [
    EngineVariant(
        id: 'cu128',
        label: 'NVIDIA CUDA 12.8',
        description: '最新驱动推荐（cuDNN 9）',
        isAmd: false),
    EngineVariant(
        id: 'cu122',
        label: 'NVIDIA CUDA 12.2',
        description: '较旧驱动',
        isAmd: false),
    EngineVariant(
        id: 'cu118',
        label: 'NVIDIA CUDA 11.8',
        description: '老驱动/老显卡',
        isAmd: false),
    EngineVariant(
        id: 'gfx120x_all',
        label: 'AMD ROCm gfx120x',
        description: 'RDNA4',
        isAmd: true),
    EngineVariant(
        id: 'gfx110x_all',
        label: 'AMD ROCm gfx110x',
        description: 'RDNA3',
        isAmd: true),
    EngineVariant(
        id: 'gfx103x_dgpu',
        label: 'AMD ROCm gfx103x',
        description: 'RDNA2',
        isAmd: true),
    EngineVariant(
        id: 'gfx101x_dgpu',
        label: 'AMD ROCm gfx101x',
        description: 'RDNA1',
        isAmd: true),
  ];
}

/// 模型文件下载规格（HuggingFace 仓库文件 → models/ 内相对路径）。
class ModelFileSpec {
  final String repo;
  final String remoteName;
  final String destRelPath;

  /// 已知的远端改名（如 VAD：model.onnx → whisper_vad.onnx）
  const ModelFileSpec({
    required this.repo,
    required this.remoteName,
    required this.destRelPath,
  });
}

/// 引擎安装状态探测结果。
class EngineProbeResult {
  final bool installed;
  final String? exePath;
  final bool hasVad;
  final bool hasMainModel;

  const EngineProbeResult({
    this.installed = false,
    this.exePath,
    this.hasVad = false,
    this.hasMainModel = false,
  });

  bool get modelsReady => hasVad && hasMainModel;
}

/// AI 翻译引擎（ChickenRice）内置安装器。
///
/// 从上游 GitHub Release 下载 nomodel 运行时（2GB 分卷 → 合并 →
/// SHA-256 校验 → 解压），再从 HuggingFace（hf-mirror.com 回退）下载
/// VAD / whisper-base / 主模型，装到用户自选目录，实现开箱即用。
///
/// 法律依据：上游为 MIT（Copyright (c) 2025 TransWithAI），本项目同为
/// MIT；集成时保留上游版权声明（见 THIRD-PARTY.md）。
class ChickenRiceEngineService {
  ChickenRiceEngineService({
    ChunkDownloader? downloader,
    Dio? apiDio,
    Future<int> Function(String dir)? freeSpaceBytes,
  })  : downloader = downloader ?? ChunkDownloader(),
        _apiDio = apiDio ?? Dio(),
        _freeSpaceBytes = freeSpaceBytes ?? _defaultFreeSpaceBytes {
    _apiDio.options.connectTimeout = const Duration(seconds: 15);
  }

  static const String upstreamRepo =
      'TransWithAI/Faster-Whisper-TransWithAI-ChickenRice';
  static const String _releaseApiUrl =
      'https://api.github.com/repos/$upstreamRepo/releases/latest';
  static const String hfHost = 'https://huggingface.co';
  static const String hfMirrorHost = 'https://hf-mirror.com';

  /// 下载/解压/模型的磁盘余量要求（除分卷+zip 双份占用外的冗余）
  static const int _extraSpaceReserve = 5 * 1024 * 1024 * 1024;

  final ChunkDownloader downloader;
  final Dio _apiDio;
  final Future<int> Function(String dir) _freeSpaceBytes;

  CancelToken? _activeToken;
  bool _cancelRequested = false;

  /// 应用代理（透传给下载器与 API 客户端）
  set proxy(String proxy) {
    downloader.proxy = proxy;
    _apiDio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (uri) => proxy;
        return client;
      },
    );
  }

  /// 请求取消进行中的安装（当前请求结束后生效）
  void requestCancel() {
    _cancelRequested = true;
    _activeToken?.cancel('安装已取消');
  }

  // -------------------------------------------------------- naming/urls

  /// 变体对应的 nomodel 资产基础名（不含分卷后缀）
  static String assetBaseName(String variant) =>
      'faster_whisper_transwithai_windows_$variant-nomodel.zip';

  /// HuggingFace 文件直链（[mirror]=true 时用 hf-mirror.com）
  static String hfFileUrl(String repo, String file, {bool mirror = false}) =>
      '${mirror ? hfMirrorHost : hfHost}/$repo/resolve/main/$file';

  /// HF API 文件树（拿主模型文件清单与大小）
  static String hfTreeApiUrl(String repo) =>
      '$hfHost/api/models/$repo/tree/main';

  /// 任务对应的默认主模型 HF 仓库
  static String mainModelRepo(String task) => task == 'transcribe'
      ? 'TransWithAI/whisper-ja-1.5B-ct2'
      : 'chickenrice0721/whisper-large-v2-translate-zh-v0.2-st-ct2';

  /// 固定模型文件：VAD（改名落 models/ 根）+ whisper-base 特征提取配置
  static const List<ModelFileSpec> fixedModelSpecs = [
    ModelFileSpec(
        repo: 'TransWithAI/Whisper-Vad-EncDec-ASMR-onnx',
        remoteName: 'model.onnx',
        destRelPath: 'whisper_vad.onnx'),
    ModelFileSpec(
        repo: 'TransWithAI/Whisper-Vad-EncDec-ASMR-onnx',
        remoteName: 'model_metadata.json',
        destRelPath: 'whisper_vad_metadata.json'),
    ModelFileSpec(
        repo: 'openai/whisper-base',
        remoteName: 'preprocessor_config.json',
        destRelPath: 'whisper-base/preprocessor_config.json'),
    ModelFileSpec(
        repo: 'openai/whisper-base',
        remoteName: 'config.json',
        destRelPath: 'whisper-base/config.json'),
    ModelFileSpec(
        repo: 'openai/whisper-base',
        remoteName: 'tokenizer.json',
        destRelPath: 'whisper-base/tokenizer.json'),
    ModelFileSpec(
        repo: 'openai/whisper-base',
        remoteName: 'vocab.json',
        destRelPath: 'whisper-base/vocab.json'),
  ];

  /// 主模型只下载这些扩展名（与上游 download_models.py 一致）
  static const List<String> _mainModelExtensions = [
    '.json',
    '.bin',
    '.txt',
    '.onnx',
    '.safetensors',
    '.model',
  ];

  // ------------------------------------------------------------ install

  /// 完整安装流程。返回 true = 安装成功。
  ///
  /// [installDir] 用户自选安装目录；[variant] EngineVariant.id；
  /// [task] translate/transcribe（决定主模型）。
  /// 通过 [onState] 推送进度；中途可 [requestCancel]。
  Future<String?> install({
    required String installDir,
    required String variant,
    required String task,
    required void Function(EngineInstallState) onState,
  }) async {
    _cancelRequested = false;
    final token = CancelToken();
    _activeToken = token;

    void emit(EngineInstallState s) => onState(s);

    try {
      // 1) 发现 Release：tag + manifest 资产 URL
      emit(const EngineInstallState(
          phase: EnginePhase.fetchingRelease, message: '获取上游 Release 信息…'));
      final release = await _fetchLatestRelease(token);
      if (release == null) {
        emit(const EngineInstallState(
            phase: EnginePhase.failed,
            message: '获取上游 Release 失败',
            error: '无法访问 GitHub API（检查网络/代理）'));
        return null;
      }
      final tagName = release['tag_name'] as String? ?? '';
      final assets = (release['assets'] as List? ?? const [])
          .map((e) => e as Map<String, dynamic>)
          .toList();
      final baseName = assetBaseName(variant);
      final manifestAsset = assets.firstWhere(
        (a) => a['name'] == '$baseName.manifest',
        orElse: () => <String, dynamic>{},
      );
      if (manifestAsset.isEmpty || tagName.isEmpty) {
        emit(EngineInstallState(
            phase: EnginePhase.failed,
            message: '未找到该变体的发行包',
            error: '上游 Release（$tagName）缺少 $baseName.manifest'));
        return null;
      }

      // 2) 下载并解析 manifest
      final manifestUrl = manifestAsset['browser_download_url'] as String;
      final manifest = await _fetchManifest(manifestUrl, token);
      if (manifest == null || manifest.chunks.isEmpty) {
        emit(const EngineInstallState(
            phase: EnginePhase.failed,
            message: 'manifest 解析失败',
            error: '分卷清单下载失败或格式异常'));
        return null;
      }

      // 3) 磁盘预检：分卷 + 合并 zip 双份 + 解压 + 模型冗余
      final required = manifest.size * 2 + _extraSpaceReserve;
      final free = await _freeSpaceBytes(installDir);
      if (free > 0 && free < required) {
        emit(EngineInstallState(
            phase: EnginePhase.failed,
            message: '磁盘空间不足',
            error: '需要约 ${_gb(required)} GB，当前剩余 ${_gb(free)} GB'));
        return null;
      }

      final dlDir = Directory(p.join(installDir, '.asmr_engine_dl'));
      await dlDir.create(recursive: true);

      // 4) 逐分卷下载（断点续传由 ChunkDownloader 保证）
      final chunkUrls = <String>[
        for (final c in manifest.chunks)
          manifestUrl.replaceAll('$baseName.manifest', c),
      ];
      for (var i = 0; i < chunkUrls.length; i++) {
        if (_cancelRequested) return _emitCanceled(emit);
        final chunkPath = p.join(dlDir.path, manifest.chunks[i]);
        emit(EngineInstallState(
            phase: EnginePhase.downloading,
            message: '下载运行时 ${i + 1}/${chunkUrls.length}',
            stepIndex: i + 1,
            stepCount: chunkUrls.length,
            total: manifest.chunkLength(i)));
        final ok = await downloader.download(
          url: chunkUrls[i],
          savePath: chunkPath,
          fileSize: manifest.chunkLength(i),
          cancelToken: token,
          onProgress: (received, total) => emit(EngineInstallState(
              phase: EnginePhase.downloading,
              message: '下载运行时 ${i + 1}/${chunkUrls.length}',
              stepIndex: i + 1,
              stepCount: chunkUrls.length,
              received: received,
              total: total)),
        );
        if (!ok) {
          if (_cancelRequested || token.isCancelled) return _emitCanceled(emit);
          emit(const EngineInstallState(
              phase: EnginePhase.failed,
              message: '分卷下载失败',
              error: '网络错误，重新安装可从断点续传'));
          return null;
        }
      }

      // 5) 合并 + SHA-256 校验
      final zipPath = p.join(dlDir.path, manifest.name);
      if (!await _mergeAndVerify(
          manifest, dlDir.path, zipPath, token, emit)) {
        return _cancelRequested || token.isCancelled
            ? _emitCanceled(emit)
            : null;
      }

      // 6) 解压（系统 tar 优先，archive 包兜底）
      emit(const EngineInstallState(
          phase: EnginePhase.extracting, message: '解压运行时（可能需要几分钟）…'));
      final extracted = await _extract(zipPath, installDir);
      if (!extracted) {
        emit(const EngineInstallState(
            phase: EnginePhase.failed,
            message: '解压失败',
            error: 'zip 解压出错，请重试或更换安装目录'));
        return null;
      }

      // 7) 定位 infer.exe（zip 可能带顶层目录）
      final exePath = await _findInferExe(Directory(installDir));
      if (exePath == null) {
        emit(const EngineInstallState(
            phase: EnginePhase.failed,
            message: '解压产物异常',
            error: '未在安装目录中找到 infer.exe'));
        return null;
      }
      final exeDir = p.dirname(exePath);

      // 8) 清理分卷与合并 zip
      try {
        await dlDir.delete(recursive: true);
      } catch (_) {}

      // 9) 模型下载（VAD + whisper-base + 主模型）
      final modelsDir = p.join(exeDir, 'models');
      final modelsOk = await _downloadModels(modelsDir, task, token, emit);
      if (!modelsOk) {
        if (_cancelRequested || token.isCancelled) return _emitCanceled(emit);
        // 运行时已装好：提示失败但保留 exe，用户可重试补模型
        emit(const EngineInstallState(
            phase: EnginePhase.failed,
            message: '模型下载失败',
            error: '运行时已安装，重新安装可只补下模型（文件已存在会跳过）'));
        return null;
      }

      emit(const EngineInstallState(
          phase: EnginePhase.done, message: 'AI 翻译引擎安装完成'));
      Log.info('engine installed: $exePath');
      return exePath;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel || _cancelRequested) {
        return _emitCanceled(emit);
      }
      emit(EngineInstallState(
          phase: EnginePhase.failed, message: '网络错误', error: '$e'));
      return null;
    } catch (e) {
      Log.error('engine install failed: $e');
      emit(EngineInstallState(
          phase: EnginePhase.failed, message: '安装失败', error: '$e'));
      return null;
    } finally {
      _activeToken = null;
    }
  }

  String? _emitCanceled(void Function(EngineInstallState) emit) {
    emit(const EngineInstallState(
        phase: EnginePhase.canceled,
        message: '安装已取消',
        error: '已下载部分已保留，重新安装将断点续传'));
    return null;
  }

  // ------------------------------------------------------- release api

  Future<Map<String, dynamic>?> _fetchLatestRelease(CancelToken token) async {
    try {
      final resp = await _apiDio.get<Map<String, dynamic>>(_releaseApiUrl,
          cancelToken: token,
          options: Options(headers: {'Accept': 'application/vnd.github+json'}));
      return resp.data;
    } catch (e) {
      Log.warning('fetch upstream release failed: $e');
      return null;
    }
  }

  Future<EngineManifest?> _fetchManifest(String url, CancelToken token) async {
    try {
      final resp = await _apiDio.get<String>(url,
          cancelToken: token, options: Options(responseType: ResponseType.plain));
      return EngineManifest.fromJson(
          json.decode(resp.data ?? '') as Map<String, dynamic>);
    } catch (e) {
      Log.warning('fetch manifest failed: $url\nerror: $e');
      return null;
    }
  }

  // -------------------------------------------------- merge and verify

  /// 流式合并全部分卷并同步计算 SHA-256；校验失败删除合并文件。
  Future<bool> _mergeAndVerify(
    EngineManifest manifest,
    String dlDir,
    String zipPath,
    CancelToken token,
    void Function(EngineInstallState) emit,
  ) async {
    emit(const EngineInstallState(
        phase: EnginePhase.merging, message: '合并分卷并校验（SHA-256）…'));
    final zipFile = File(zipPath);
    if (await zipFile.exists()) await zipFile.delete();

    // crypto 包的增量摘要：startChunkedConversion 返回可逐块喂的 sink
    Digest? computed;
    final digestSink = sha256.startChunkedConversion(
        _DigestOutput((d) => computed = d));
    final sink = zipFile.openWrite();
    var merged = 0;
    try {
      for (final chunkName in manifest.chunks) {
        final chunkFile = File(p.join(dlDir, chunkName));
        if (!await chunkFile.exists()) {
          Log.error('engine merge failed: missing chunk $chunkName');
          return false;
        }
        await for (final piece in chunkFile.openRead()) {
          if (token.isCancelled || _cancelRequested) return false;
          digestSink.add(piece);
          sink.add(piece);
          merged += piece.length;
          emit(EngineInstallState(
              phase: EnginePhase.merging,
              message: '合并分卷并校验（SHA-256）…',
              received: merged,
              total: manifest.size));
        }
      }
      await sink.close();
      digestSink.close();
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      digestSink.close();
      Log.error('engine merge failed: $e');
      await _deleteIfExists(zipFile);
      return false;
    }

    emit(const EngineInstallState(
        phase: EnginePhase.verifying, message: '校验完成，整理文件…'));
    final actual = (computed?.toString() ?? '').toLowerCase();
    if (actual != manifest.hash) {
      Log.error('engine zip hash mismatch: expected ${manifest.hash}, '
          'got $actual');
      await _deleteIfExists(zipFile);
      emit(const EngineInstallState(
          phase: EnginePhase.failed,
          message: '完整性校验失败',
          error: 'SHA-256 不匹配，已删除损坏文件，请重新下载'));
      return false;
    }
    return true;
  }

  // ----------------------------------------------------------- extract

  /// 解压 zip 到 [destDir]：优先系统 tar（Windows 10+ 自带），
  /// 失败回退 archive 包（3.5GB 大文件下内存占用较高，仅兜底）。
  Future<bool> _extract(String zipPath, String destDir) async {
    try {
      final result = await Process.run('tar', ['-xf', zipPath, '-C', destDir]);
      if (result.exitCode == 0) {
        Log.info('engine extracted via tar: $destDir');
        return true;
      }
      Log.warning('tar extract failed (exit ${result.exitCode}): '
          '${result.stderr}');
    } catch (e) {
      Log.warning('tar unavailable, fallback to archive package: $e');
    }
    try {
      // 兜底：archive 包内存解包（3.5GB 大文件下内存占用高，仅 tar 不可用时）
      final bytes = File(zipPath).readAsBytesSync();
      return _extractWithArchive(bytes, destDir);
    } catch (e) {
      Log.error('archive extract failed: $e');
      return false;
    }
  }

  bool _extractWithArchive(List<int> bytes, String destDir) {
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final entry in archive) {
      final outPath = p.join(destDir, entry.name);
      if (!p.isWithin(destDir, outPath) && outPath != destDir) {
        Log.warning('skip suspicious zip entry: ${entry.name}');
        continue;
      }
      if (entry.isFile) {
        final out = File(outPath)..createSync(recursive: true);
        out.writeAsBytesSync(entry.content as List<int>);
      } else {
        Directory(outPath).createSync(recursive: true);
      }
    }
    Log.info('engine extracted via archive package: $destDir');
    return true;
  }

  /// 在 [root] 下（限 4 层深度）查找 infer.exe。
  Future<String?> _findInferExe(Directory root, {int depth = 0}) async {
    if (depth > 4 || !await root.exists()) return null;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is File &&
          p.basename(entity.path).toLowerCase() == 'infer.exe') {
        return entity.path;
      }
    }
    await for (final entity in root.list(followLinks: false)) {
      if (entity is Directory) {
        final name = p.basename(entity.path);
        if (name.startsWith('.') || name == 'models') continue;
        final found = await _findInferExe(entity, depth: depth + 1);
        if (found != null) return found;
      }
    }
    return null;
  }

  // ------------------------------------------------------------ models

  /// 下载全部模型到 [modelsDir]；文件已存在则跳过（补下载语义）。
  Future<bool> _downloadModels(
    String modelsDir,
    String task,
    CancelToken token,
    void Function(EngineInstallState) emit,
  ) async {
    final modelRepo = mainModelRepo(task);

    // 主模型文件清单：HF API 获取（含大小），失败则用已知必备文件兜底
    final mainFiles = await _fetchMainModelFiles(modelRepo, token);
    final specs = <ModelFileSpec>[
      ...fixedModelSpecs,
      for (final f in mainFiles)
        ModelFileSpec(repo: modelRepo, remoteName: f, destRelPath: f),
    ];

    for (var i = 0; i < specs.length; i++) {
      if (_cancelRequested || token.isCancelled) return false;
      final spec = specs[i];
      final destPath = p.join(modelsDir, spec.destRelPath);
      if (File(destPath).existsSync()) continue;

      emit(EngineInstallState(
          phase: EnginePhase.downloadingModels,
          message: '下载模型 ${i + 1}/${specs.length}：${p.basename(spec.destRelPath)}',
          stepIndex: i + 1,
          stepCount: specs.length));

      final ok = await _downloadHfFile(
        repo: spec.repo,
        remoteName: spec.remoteName,
        destPath: destPath,
        token: token,
        onProgress: (received, total) => emit(EngineInstallState(
            phase: EnginePhase.downloadingModels,
            message:
                '下载模型 ${i + 1}/${specs.length}：${p.basename(spec.destRelPath)}',
            stepIndex: i + 1,
            stepCount: specs.length,
            received: received,
            total: total)),
      );
      if (!ok) return false;
    }
    return true;
  }

  /// 下载单个 HF 文件：主源失败自动回退 hf-mirror.com（与上游一致）。
  Future<bool> _downloadHfFile({
    required String repo,
    required String remoteName,
    required String destPath,
    required CancelToken token,
    void Function(int, int)? onProgress,
  }) async {
    final urls = [
      hfFileUrl(repo, remoteName),
      hfFileUrl(repo, remoteName, mirror: true),
    ];
    for (final url in urls) {
      if (_cancelRequested || token.isCancelled) return false;
      final ok = await downloader.download(
        url: url,
        savePath: destPath,
        threadCount: 1,
        cancelToken: token,
        onProgress: onProgress,
      );
      if (ok) return true;
      if (_cancelRequested || token.isCancelled) return false;
      Log.warning('hf download failed, trying mirror: $url');
    }
    return false;
  }

  /// 主模型仓库的文件清单（按扩展名过滤）；API 不可用时返回必备文件兜底。
  Future<List<String>> _fetchMainModelFiles(
      String repo, CancelToken token) async {
    try {
      final resp = await _apiDio.get<List<dynamic>>(hfTreeApiUrl(repo),
          cancelToken: token);
      final files = <String>[];
      for (final item in resp.data ?? const []) {
        final m = item as Map<String, dynamic>;
        if (m['type'] != 'file') continue;
        final path = m['path'] as String? ?? '';
        if (_mainModelExtensions.any((e) => path.toLowerCase().endsWith(e))) {
          files.add(path);
        }
      }
      if (files.isNotEmpty) return files;
    } catch (e) {
      Log.warning('fetch hf model tree failed: $repo\nerror: $e');
    }
    // 兜底：常见文件名（与上游 download_models.py 一致）
    return const [
      'config.json',
      'model.bin',
      'preprocessor_config.json',
      'tokenizer.json',
      'vocabulary.json',
    ];
  }

  // ------------------------------------------------------------- probe

  /// 探测 [installDir] 内的引擎完整性（供 UI 显示安装状态）。
  Future<EngineProbeResult> probe(String? installDir) async {
    if (installDir == null || installDir.isEmpty) {
      return const EngineProbeResult();
    }
    final dir = Directory(installDir);
    if (!await dir.exists()) return const EngineProbeResult();
    final exePath = await _findInferExe(dir);
    if (exePath == null) return const EngineProbeResult();

    final modelsDir = Directory(p.join(p.dirname(exePath), 'models'));
    final hasVad =
        await File(p.join(modelsDir.path, 'whisper_vad.onnx')).exists();
    var hasMainModel = false;
    if (await modelsDir.exists()) {
      await for (final e in modelsDir.list(followLinks: false)) {
        final name = p.basename(e.path).toLowerCase();
        if (e is File &&
            (name == 'model.bin' ||
                name == 'model.safetensors' ||
                name == 'pytorch_model.bin')) {
          hasMainModel = true;
          break;
        }
      }
    }
    return EngineProbeResult(
      installed: true,
      exePath: exePath,
      hasVad: hasVad,
      hasMainModel: hasMainModel,
    );
  }

  // ------------------------------------------------------------- utils

  static Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  static String _gb(int bytes) =>
      (bytes / (1024 * 1024 * 1024)).toStringAsFixed(1);

  /// 目标目录所在磁盘剩余空间（字节）。
  /// Windows 用 PowerShell 查询；失败/非 Windows 返回 -1（调用方跳过检查）。
  static Future<int> _defaultFreeSpaceBytes(String dir) async {
    if (!Platform.isWindows) return -1;
    try {
      final drive = p.rootPrefix(dir).replaceAll('\\', '').replaceAll('/', '');
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          "(Get-Volume -DriveLetter '$drive').SizeRemaining",
        ],
      );
      if (result.exitCode != 0) return -1;
      return int.tryParse('${result.stdout}'.trim()) ?? -1;
    } catch (e) {
      Log.warning('free space query failed: $e');
      return -1;
    }
  }
}

/// sha256.startChunkedConversion 的输出接收器（拿到最终 Digest）。
class _DigestOutput implements Sink<Digest> {
  _DigestOutput(this._onDigest);
  final void Function(Digest) _onDigest;

  @override
  void add(Digest data) => _onDigest(data);

  @override
  void close() {}
}
