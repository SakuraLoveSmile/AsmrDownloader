import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:asmr_downloader/services/download/chunk_downloader.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// GitHub Release 最新版本信息。
class UpdateInfo {
  const UpdateInfo({
    required this.tagName,
    required this.version,
    required this.releaseNotes,
    required this.assetUrl,
    required this.assetSize,
    required this.htmlUrl,
    this.checksumsUrl = '',
    this.assetSha256 = '',
  });

  /// Release tag（如 v0.9.0）
  final String tagName;

  /// 去掉 v 前缀的版本号（如 0.9.0）
  final String version;

  /// Release 说明正文
  final String releaseNotes;

  /// 当前平台安装包的下载地址
  final String assetUrl;

  /// 安装包大小（字节；0 = API 未返回）
  final int assetSize;

  /// Release 网页地址（手动下载兜底）
  final String htmlUrl;

  /// Release 内 SHA256SUMS 文件的下载地址；空 = 未提供（跳过校验）
  final String checksumsUrl;

  /// 平台 zip 的 SHA-256（小写 hex，来自 SHA256SUMS）；空 = 未知
  final String assetSha256;

  UpdateInfo copyWith({String? assetSha256}) => UpdateInfo(
        tagName: tagName,
        version: version,
        releaseNotes: releaseNotes,
        assetUrl: assetUrl,
        assetSize: assetSize,
        htmlUrl: htmlUrl,
        checksumsUrl: checksumsUrl,
        assetSha256: assetSha256 ?? this.assetSha256,
      );
}

/// 一次更新检查的结果：携带 ETag 与响应体供调用方缓存，
/// 下次检查作条件请求（Release 未变化时返回 304，不消耗速率配额）。
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.info,
    required this.etag,
    required this.releaseBody,
  });

  /// 新版本信息；null = 当前已是最新
  final UpdateInfo? info;

  /// 本次响应的 ETag（304 时沿用传入值）
  final String? etag;

  /// 最新 Release 的原始 JSON（304 时沿用传入值）
  final String? releaseBody;
}

/// 更新检查失败（message 为用户可读原因，区分速率限制等）。
class UpdateCheckException implements Exception {
  UpdateCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 应用自动更新服务：检测 GitHub Release 新版本、下载安装包、
/// 生成辅助脚本完成「退出 → 替换文件 → 重启」的原地更新。
///
/// 发布产物为 zip 绿色版（见 .github/workflows/windows-release.yml）：
/// - Windows：zip 根目录即程序文件（平铺）
/// - macOS：zip 根目录含 AsmrDownloader.app
/// 运行中的 exe / .app 被占用，替换由应用退出后执行的脚本完成。
class UpdateService {
  UpdateService({
    ChunkDownloader? downloader,
    Dio? apiDio,
    Future<bool> Function(String zipPath, String destDir)? extractor,
    Future<bool> Function(String executable, List<String> arguments)?
        scriptLauncher,
    void Function(int code)? exitFn,
  })  : downloader = downloader ?? ChunkDownloader(),
        _apiDio = apiDio ?? Dio(),
        _extractor = extractor ?? _defaultExtract,
        _scriptLauncher = scriptLauncher ?? _defaultLaunchScript,
        _exitFn = exitFn ?? exit {
    _apiDio.options
      ..connectTimeout = const Duration(seconds: 15)
      ..receiveTimeout = const Duration(seconds: 15)
      ..headers['User-Agent'] = 'AsmrDownloader-UpdateChecker'
      ..headers['Accept'] = 'application/vnd.github+json';
    _installAuthFallback();
  }

  /// GitHub Token 无效（401）时自动降级为匿名重试一次：
  /// 避免 Token 失效后更新检查/引擎安装整体不可用；
  /// 重试成功后本实例不再携带认证头（日志提示用户检查 Token）。
  void _installAuthFallback() {
    _apiDio.interceptors.add(InterceptorsWrapper(
      onError: (e, handler) async {
        if (e.response?.statusCode == 401 &&
            _apiDio.options.headers.containsKey('Authorization')) {
          _apiDio.options.headers.remove('Authorization');
          Log.warning('github token rejected (401), retrying anonymously');
          try {
            // 重新构造请求（不复用已消费的 requestOptions）
            final resp = await _apiDio.request(
              e.requestOptions.path,
              options: Options(
                method: e.requestOptions.method,
                headers: Map.of(e.requestOptions.headers)
                  ..remove('Authorization'),
                responseType: e.requestOptions.responseType,
                validateStatus: e.requestOptions.validateStatus,
              ),
            );
            handler.resolve(resp);
            return;
          } catch (err) {
            handler.next(err is DioException ? err : e);
            return;
          }
        }
        handler.next(e);
      },
    ));
  }

  static const String repo = 'SakuraLoveSmile/AsmrDownloader';
  static const String releaseApiUrl =
      'https://api.github.com/repos/$repo/releases/latest';

  final ChunkDownloader downloader;
  final Dio _apiDio;
  final Future<bool> Function(String zipPath, String destDir) _extractor;
  final Future<bool> Function(String executable, List<String> arguments)
      _scriptLauncher;
  final void Function(int code) _exitFn;

  CancelToken? _activeToken;

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

  /// GitHub API 认证 token（可选）：认证后限额 5000 次/小时/账号，
  /// 避免匿名 60 次/小时/IP 限流（读取公开仓库无需任何 scope）。
  /// 空 = 移除认证头，恢复匿名请求。
  set githubToken(String token) {
    final t = token.trim();
    if (t.isEmpty) {
      _apiDio.options.headers.remove('Authorization');
    } else {
      _apiDio.options.headers['Authorization'] = 'Bearer $t';
    }
  }

  /// 请求取消进行中的下载
  void requestCancel() {
    _activeToken?.cancel('更新下载已取消');
  }

  // ------------------------------------------------------------- version

  /// 当前平台安装包的 asset 名后缀；不支持的平台返回 null。
  static String? get platformAssetSuffix {
    if (Platform.isWindows) return '-Windows.zip';
    if (Platform.isMacOS) return '-macOS.zip';
    return null;
  }

  /// [latest] 是否严格新于 [current]。
  /// 支持 v/V 前缀；段按数值比较，缺失段视为 0；
  /// 数值部分相同时，带预发布后缀（如 -beta.1）的视为旧版。
  static bool isNewerVersion(String current, String latest) {
    final c = _parseVersion(current);
    final l = _parseVersion(latest);
    if (c == null || l == null) return false;
    final n = c.$1.length > l.$1.length ? c.$1.length : l.$1.length;
    for (var i = 0; i < n; i++) {
      final a = i < c.$1.length ? c.$1[i] : 0;
      final b = i < l.$1.length ? l.$1[i] : 0;
      if (a != b) return b > a;
    }
    // 数值部分相同：正式版新于预发布版
    return c.$2 && !l.$2;
  }

  /// 解析版本号为（数值段列表, 是否预发布）；非法返回 null。
  static (List<int>, bool)? _parseVersion(String s) {
    var t = s.trim();
    if (t.isEmpty) return null;
    if (t[0] == 'v' || t[0] == 'V') t = t.substring(1);
    final dash = t.indexOf('-');
    final prerelease = dash >= 0;
    final numPart = dash >= 0 ? t.substring(0, dash) : t;
    final nums = <int>[];
    for (final seg in numPart.split('.')) {
      final v = int.tryParse(seg);
      if (v == null) return null;
      nums.add(v);
    }
    if (nums.isEmpty) return null;
    return (nums, prerelease);
  }

  /// 解析 Release JSON，按 [assetSuffix] 匹配当前平台安装包。
  /// 缺少 tag 或匹配不到 asset 时返回 null。
  static UpdateInfo? parseRelease(
    Map<String, dynamic> release, {
    required String assetSuffix,
  }) {
    final tagName = (release['tag_name'] as String? ?? '').trim();
    if (tagName.isEmpty) return null;
    final assets = (release['assets'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    Map<String, dynamic>? matched;
    for (final a in assets) {
      if ((a['name'] as String? ?? '').endsWith(assetSuffix)) {
        matched = a;
        break;
      }
    }
    final url = matched?['browser_download_url'] as String? ?? '';
    if (url.isEmpty) return null;
    var version = tagName;
    if (version.startsWith('v') || version.startsWith('V')) {
      version = version.substring(1);
    }
    // SHA256SUMS 文件（含全部 zip 的 SHA-256），供下载后完整性校验
    String checksumsUrl = '';
    for (final a in assets) {
      if ((a['name'] as String? ?? '') == 'SHA256SUMS') {
        checksumsUrl = a['browser_download_url'] as String? ?? '';
        break;
      }
    }
    return UpdateInfo(
      tagName: tagName,
      version: version,
      releaseNotes: release['body'] as String? ?? '',
      assetUrl: url,
      assetSize: (matched?['size'] as num?)?.toInt() ?? 0,
      htmlUrl: release['html_url'] as String? ?? '',
      checksumsUrl: checksumsUrl,
    );
  }

  /// 从 sha256sum 格式文本（`<hex>  <filename>` 每行一条）中提取
  /// [fileName] 的哈希；非法/缺失返回空串。
  static String extractSha256For(String sumsText, String fileName) {
    for (final line in sumsText.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length >= 2 && parts.last == fileName) {
        final hex = parts.first.toLowerCase();
        if (RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) return hex;
      }
    }
    return '';
  }

  /// 流式计算文件 SHA-256（不整体载入内存）。
  static Future<String> sha256OfFile(String path) async {
    final digest = await sha256.bind(File(path).openRead()).first;
    return digest.toString();
  }

  // --------------------------------------------------------------- check

  /// 从 Release JSON 响应体判定新版本（无网络；供检查与节流缓存复用）。
  /// 无新版/解析失败返回 null。
  static UpdateInfo? evaluateRelease(
      String? releaseBody, String currentVersion) {
    final suffix = platformAssetSuffix;
    if (suffix == null || releaseBody == null || releaseBody.isEmpty) {
      return null;
    }
    try {
      final release = json.decode(releaseBody) as Map<String, dynamic>;
      final info = parseRelease(release, assetSuffix: suffix);
      if (info == null) return null;
      return isNewerVersion(currentVersion, info.version) ? info : null;
    } catch (_) {
      return null;
    }
  }

  /// 检查是否有新版本；无新版返回 info = null，失败抛
  /// [UpdateCheckException]（含用户可读原因）。
  ///
  /// [etag]/[cachedReleaseBody] 为上次成功检查的缓存：带 ETag 发起
  /// 条件请求，Release 未变化时 GitHub 返回 304 且不消耗速率配额
  /// （匿名限额 60 次/小时/IP，共享代理出口 IP 时极易触发 403 限流）。
  Future<UpdateCheckResult> checkForUpdate(
    String currentVersion, {
    String? etag,
    String? cachedReleaseBody,
  }) async {
    final suffix = platformAssetSuffix;
    if (suffix == null) {
      return UpdateCheckResult(
          info: null, etag: etag, releaseBody: cachedReleaseBody);
    }
    try {
      final resp = await _apiDio.getUri<String>(
        Uri.parse(releaseApiUrl),
        options: Options(
          responseType: ResponseType.plain,
          // 304 = ETag 命中（Release 未变化），按成功处理
          validateStatus: (status) => status == 200 || status == 304,
          headers: etag == null ? null : {'if-none-match': etag},
        ),
      );
      final newEtag = resp.headers.value(HttpHeaders.etagHeader) ?? etag;
      if (resp.statusCode == 304) {
        // Release 未变化：复用上次响应体重新判定（当前版本可能已升级）
        return UpdateCheckResult(
          info: await _attachChecksum(
              evaluateRelease(cachedReleaseBody, currentVersion)),
          etag: newEtag,
          releaseBody: cachedReleaseBody,
        );
      }
      final body = resp.data;
      return UpdateCheckResult(
        info: await _attachChecksum(evaluateRelease(body, currentVersion)),
        etag: newEtag,
        releaseBody: body,
      );
    } on DioException catch (e) {
      Log.warning('check update request failed\n'
          'type: ${e.type}\nerror: $e');
      throw _toCheckException(e);
    } catch (e) {
      throw UpdateCheckException('检查更新失败：$e');
    }
  }

  /// Release 提供 SHA256SUMS 时拉取并提取当前平台 zip 的哈希，
  /// 附着到 [UpdateInfo.assetSha256]；拉取失败仅告警（下载时跳过校验）。
  Future<UpdateInfo?> _attachChecksum(UpdateInfo? info) async {
    if (info == null || info.checksumsUrl.isEmpty) return info;
    try {
      final resp = await _apiDio.getUri<String>(
        Uri.parse(info.checksumsUrl),
        options: Options(responseType: ResponseType.plain),
      );
      final fileName = p.basename(Uri.parse(info.assetUrl).path);
      final sha = extractSha256For(resp.data ?? '', fileName);
      if (sha.isEmpty) {
        Log.warning('SHA256SUMS has no entry for $fileName');
        return info;
      }
      return info.copyWith(assetSha256: sha);
    } catch (e) {
      Log.warning('fetch SHA256SUMS failed: ${info.checksumsUrl}\nerror: $e');
      return info;
    }
  }

  /// 把检查请求的网络错误转换为用户可读原因（区分速率限制）。
  /// 网络层错误带底层原因（连接被拒/超时/TLS 等），便于定位。
  static UpdateCheckException _toCheckException(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401) {
      return UpdateCheckException('GitHub Token 无效或已过期，请在设置中清除或更换');
    }
    final remaining = e.response?.headers.value('x-ratelimit-remaining');
    if ((status == 403 && remaining == '0') || status == 429) {
      return UpdateCheckException('GitHub API 速率限制（未认证限额 60 次/小时/IP，'
          '共享代理出口时常见），请稍后再试；'
          '可在设置中配置 GitHub Token 提升限额');
    }
    if (status == 403) {
      return UpdateCheckException('GitHub API 拒绝访问（403）');
    }
    if (status == 404) {
      return UpdateCheckException('未找到 Release（仓库尚未发布版本）');
    }
    String hint;
    switch (e.type) {
      case DioExceptionType.connectionError:
        hint = '连接失败';
      case DioExceptionType.connectionTimeout:
        hint = '连接超时';
      case DioExceptionType.receiveTimeout:
        hint = '响应超时';
      case DioExceptionType.sendTimeout:
        hint = '发送超时';
      case DioExceptionType.badCertificate:
        hint = 'TLS 证书校验失败（代理可能拦截了 HTTPS）';
      default:
        hint = '网络错误';
    }
    final detail = e.message ?? (e.error?.toString() ?? '');
    return UpdateCheckException('$hint（$detail），请检查网络/代理后重试');
  }

  // ------------------------------------------------------------ download

  /// 更新包下载/解压目录：放系统临时目录。
  /// Windows 上应用数据目录可能就在安装目录内，放安装目录会导致
  /// 复制替换时自我嵌套。
  static String get _updateWorkDir =>
      p.join(Directory.systemTemp.path, 'asmr_update_dl');

  /// 下载安装包到临时目录；成功返回 zip 路径，失败返回 null。
  Future<String?> downloadUpdate(
    UpdateInfo info, {
    CancelToken? cancelToken,
    void Function(int received, int total)? onProgress,
  }) async {
    final token = cancelToken ?? CancelToken();
    _activeToken = token;
    final fileName = p.basename(Uri.parse(info.assetUrl).path);
    final savePath = p.join(_updateWorkDir, fileName);
    try {
      await Directory(_updateWorkDir).create(recursive: true);
      final ok = await downloader.download(
        url: info.assetUrl,
        savePath: savePath,
        fileSize: info.assetSize,
        cancelToken: token,
        onProgress: onProgress,
      );
      if (!ok) return null;
      // 大小校验（GitHub API 提供了 asset size）
      final size = await File(savePath).length();
      if (info.assetSize > 0 && size != info.assetSize) {
        Log.error('update package size mismatch: expect ${info.assetSize}, '
            'got $size');
        await File(savePath).delete();
        return null;
      }
      // SHA-256 校验（Release 提供 SHA256SUMS 时）
      if (info.assetSha256.isNotEmpty) {
        final actual = await sha256OfFile(savePath);
        if (actual != info.assetSha256) {
          Log.error('update package sha256 mismatch: '
              'expect ${info.assetSha256}, got $actual');
          await File(savePath).delete();
          return null;
        }
      } else {
        Log.warning('update package sha256 not verified: '
            'release has no SHA256SUMS entry for ${p.basename(savePath)}');
      }
      return savePath;
    } finally {
      _activeToken = null;
    }
  }

  // -------------------------------------------------------------- apply

  /// 解压更新包、写出平台更新脚本并启动，随后退出应用；
  /// 脚本会等待本进程退出后替换文件并重启。成功返回 true。
  ///
  /// 仅 release 构建允许（debug 构建的可执行文件是 Flutter 工具链产物，
  /// 不能被替换）。
  Future<bool> applyUpdate(String zipPath) async {
    if (!kReleaseMode) {
      Log.warning('applyUpdate skipped: not a release build');
      return false;
    }
    return prepareAndLaunchUpdate(zipPath);
  }

  /// 安装核心流程（不含 release 闸门，便于测试）：
  /// 解压 → 生成平台脚本 → 启动脚本 → 退出应用。
  Future<bool> prepareAndLaunchUpdate(String zipPath) async {
    try {
      // 1) 解压到 staging
      final stagingDir = p.join(p.dirname(zipPath), 'staging');
      if (Directory(stagingDir).existsSync()) {
        Directory(stagingDir).deleteSync(recursive: true);
      }
      Directory(stagingDir).createSync(recursive: true);
      if (!await _extractor(zipPath, stagingDir)) {
        Log.error('extract update package failed: $zipPath');
        return false;
      }

      // 2) 生成平台更新脚本
      final exePath = Platform.resolvedExecutable;
      final scriptPath = await _writeUpdateScript(exePath, stagingDir);
      if (scriptPath == null) return false;

      // 3) 启动脚本（detached），退出应用交给脚本接管
      final launched = Platform.isWindows
          ? await _scriptLauncher('wscript.exe', [
              scriptPath,
              '$pid',
              stagingDir,
              p.dirname(exePath),
              p.basename(exePath),
            ])
          : await _scriptLauncher('/bin/sh', [scriptPath]);
      if (!launched) {
        Log.error('launch updater script failed: $scriptPath');
        return false;
      }
      Log.info('update prepared, exiting for install: $scriptPath');
      _exitFn(0);
      return true;
    } catch (e) {
      Log.error('apply update failed\nerror: $e');
      return false;
    }
  }

  /// 按平台生成更新脚本，返回脚本路径；产物异常返回 null。
  ///
  /// staging 内容检查：Windows 必须包含主 exe，macOS 必须包含完整的
  /// `AsmrDownloader.app`（含 Contents/MacOS）；不得仅凭 staging 非空替换。
  Future<String?> _writeUpdateScript(String exePath, String stagingDir) async {
    final scriptDir = Directory.systemTemp.path;
    if (Platform.isWindows) {
      // zip 根目录即程序文件：staging 平铺 → 覆盖安装目录
      final installDir = p.dirname(exePath);
      final exeName = p.basename(exePath);
      if (!File(p.join(stagingDir, exeName)).existsSync()) {
        Log.error('main exe missing in staging dir: $stagingDir ($exeName)');
        return null;
      }
      final scriptPath = p.join(scriptDir, 'asmr_updater.vbs');
      await File(scriptPath).writeAsString(
          buildWindowsVbsScript(pid, stagingDir, installDir, exeName));
      return scriptPath;
    }
    if (Platform.isMacOS) {
      // zip 根目录含 .app：定位新旧 .app 路径
      final oldApp = p.dirname(p.dirname(p.dirname(exePath)));
      String? newApp;
      for (final e in Directory(stagingDir).listSync()) {
        if (e.path.endsWith('.app')) {
          newApp = e.path;
          break;
        }
      }
      if (newApp == null ||
          !Directory(p.join(newApp, 'Contents', 'MacOS')).existsSync()) {
        Log.error('valid .app not found in staging dir: $stagingDir '
            '(missing .app or Contents/MacOS)');
        return null;
      }
      final scriptPath = p.join(scriptDir, 'asmr_updater.sh');
      await File(scriptPath).writeAsString(buildMacScript(pid, newApp, oldApp));
      return scriptPath;
    }
    return null;
  }

  /// Windows 更新脚本：通过 wscript.exe 无窗口运行，等 PID 退出（最多
  /// 60 秒）→ 备份旧主程序 → 隐藏 xcopy 覆盖 → 失败回滚主程序 / 成功
  /// 重启并清理备份 → 自删。
  ///
  /// 路径不嵌入脚本：Dart 以 UTF-16 命令行参数传给 WSH，避免中文/日文
  /// 安装路径经过 VBS 源文件代码页转码。保留参数列表是为了让该方法
  /// 继续作为脚本内容的纯单元测试入口。
  static String buildWindowsVbsScript(
      int pid, String stagingDir, String installDir, String exeName) {
    return 'Option Explicit\r\n'
        'Dim shell, fso, processId, stagingDir, installDir, exeName\r\n'
        'Dim processSet, query, installExe, exeBackup, i, xcopyResult\r\n'
        'Set shell = CreateObject("WScript.Shell")\r\n'
        'Set fso = CreateObject("Scripting.FileSystemObject")\r\n'
        'If WScript.Arguments.Count < 4 Then WScript.Quit 2\r\n'
        'processId = WScript.Arguments(0)\r\n'
        'stagingDir = WScript.Arguments(1)\r\n'
        'installDir = WScript.Arguments(2)\r\n'
        'exeName = WScript.Arguments(3)\r\n'
        'For i = 1 To 60\r\n'
        '  query = "SELECT ProcessId FROM Win32_Process WHERE ProcessId=" & processId\r\n'
        '  Set processSet = Nothing\r\n'
        '  On Error Resume Next\r\n'
        '  Set processSet = GetObject("winmgmts:\\\\.\\root\\cimv2").ExecQuery(query)\r\n'
        '  Err.Clear\r\n'
        '  On Error GoTo 0\r\n'
        '  If processSet Is Nothing Then Exit For\r\n'
        '  If processSet.Count = 0 Then Exit For\r\n'
        '  WScript.Sleep 1000\r\n'
        'Next\r\n'
        'installExe = fso.BuildPath(installDir, exeName)\r\n'
        'exeBackup = installExe & ".bak"\r\n'
        'On Error Resume Next\r\n'
        'fso.CopyFile installExe, exeBackup, True\r\n'
        'On Error GoTo 0\r\n'
        'xcopyResult = shell.Run("cmd.exe /c xcopy " & Quote(stagingDir & "\\*") & " " & Quote(installDir & "\\") & " /E /Y /Q", 0, True)\r\n'
        'If xcopyResult <> 0 Then\r\n'
        '  On Error Resume Next\r\n'
        '  If fso.FileExists(exeBackup) Then fso.CopyFile exeBackup, installExe, True\r\n'
        '  On Error GoTo 0\r\n'
        '  WScript.Quit 1\r\n'
        'End If\r\n'
        'On Error Resume Next\r\n'
        'If fso.FileExists(exeBackup) Then fso.DeleteFile exeBackup, True\r\n'
        'On Error GoTo 0\r\n'
        'shell.Run Quote(installExe), 1, False\r\n'
        'fso.DeleteFile WScript.ScriptFullName, True\r\n'
        'Function Quote(value)\r\n'
        '  Quote = Chr(34) & value & Chr(34)\r\n'
        'End Function\r\n';
  }

  /// Backwards-compatible alias for callers that used the old test helper.
  static String buildWindowsScript(
          int pid, String stagingDir, String installDir, String exeName) =>
      buildWindowsVbsScript(pid, stagingDir, installDir, exeName);

  /// macOS 更新脚本：等 PID 退出 → 旧 .app 改名备份 → 移入新 .app →
  /// open 重启；移动失败时把备份改回原名（回滚）并重启旧版。
  static String buildMacScript(int pid, String newApp, String oldApp) {
    return '#!/bin/sh\n'
        '# AsmrDownloader auto updater: wait exit, backup old .app,\n'
        '# move new .app in place, restart; rollback on failure\n'
        'PID="$pid"\n'
        'NEW_APP="$newApp"\n'
        'OLD_APP="$oldApp"\n'
        'BACKUP="\$OLD_APP.bak"\n'
        'while kill -0 "\$PID" 2>/dev/null; do\n'
        '  sleep 1\n'
        'done\n'
        'if mv "\$OLD_APP" "\$BACKUP"; then\n'
        '  if mv "\$NEW_APP" "\$(dirname "\$OLD_APP")/"; then\n'
        '    open "\$OLD_APP"\n'
        '    rm -rf "\$BACKUP"\n'
        '  else\n'
        '    mv "\$BACKUP" "\$OLD_APP"\n'
        '    open "\$OLD_APP"\n'
        '  fi\n'
        'else\n'
        '  # 旧 .app 备份失败（权限等）：保守起见仍尝试原位覆盖\n'
        '  if mv "\$NEW_APP" "\$(dirname "\$OLD_APP")/"; then\n'
        '    open "\$OLD_APP"\n'
        '  fi\n'
        'fi\n'
        'rm -f "\$0"\n';
  }

  /// 在浏览器打开 Release 页面（debug 构建 / 安装失败时的兜底）。
  Future<void> openReleasePage(UpdateInfo info) async {
    if (info.htmlUrl.isEmpty) return;
    try {
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', info.htmlUrl],
            mode: ProcessStartMode.detached);
      } else if (Platform.isMacOS) {
        await Process.start('open', [info.htmlUrl],
            mode: ProcessStartMode.detached);
      }
    } catch (e) {
      Log.warning('open release page failed: ${info.htmlUrl}\nerror: $e');
    }
  }

  // ------------------------------------------------------------ extract

  /// 解压 zip 到 [destDir]：优先系统工具（macOS ditto 保留 .app 权限与
  /// 符号链接；Windows 10+ 自带 tar），失败回退 archive 包内存解包。
  static Future<bool> _defaultExtract(String zipPath, String destDir) async {
    try {
      final cmd = Platform.isMacOS ? 'ditto' : 'tar';
      final args = Platform.isMacOS
          ? ['-x', '-k', zipPath, destDir]
          : ['-xf', zipPath, '-C', destDir];
      final result = await Process.run(cmd, args);
      if (result.exitCode == 0) {
        Log.info('update package extracted via $cmd: $destDir');
        return true;
      }
      Log.warning('$cmd extract failed (exit ${result.exitCode}): '
          '${result.stderr}');
    } catch (e) {
      Log.warning('system extractor unavailable, fallback to archive: $e');
    }
    try {
      final bytes = await File(zipPath).readAsBytes();
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
      Log.info('update package extracted via archive package: $destDir');
      return true;
    } catch (e) {
      Log.error('archive extract failed: $e');
      return false;
    }
  }

  static Future<bool> _defaultLaunchScript(
      String executable, List<String> arguments) async {
    try {
      await Process.start(executable, arguments,
          mode: ProcessStartMode.detached);
      return true;
    } catch (e) {
      Log.error('start updater script failed: $executable\nerror: $e');
      return false;
    }
  }
}
