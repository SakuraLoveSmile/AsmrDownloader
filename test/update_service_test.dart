import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:asmr_downloader/services/download/chunk_downloader.dart';
import 'package:asmr_downloader/services/update/update_service.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String sha256Of(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  // 应用仅面向 Windows/macOS；Linux 仅作 CI quality-gate 运行环境，
  // 更新机制的平台相关用例在 Linux 上跳过。
  final supportedUpdatePlatform = Platform.isWindows || Platform.isMacOS;

  group('isNewerVersion 版本比较', () {
    test('更高版本 → true', () {
      expect(UpdateService.isNewerVersion('0.8.0', '0.9.0'), isTrue);
      expect(UpdateService.isNewerVersion('0.8.0', '1.0.0'), isTrue);
      expect(UpdateService.isNewerVersion('0.8.9', '0.8.10'), isTrue);
    });

    test('支持 v/V 前缀', () {
      expect(UpdateService.isNewerVersion('0.8.0', 'v0.9.0'), isTrue);
      expect(UpdateService.isNewerVersion('v0.8.0', 'V0.9.0'), isTrue);
    });

    test('同版本 / 更低版本 → false', () {
      expect(UpdateService.isNewerVersion('0.8.0', '0.8.0'), isFalse);
      expect(UpdateService.isNewerVersion('v0.9.0', '0.8.0'), isFalse);
      expect(UpdateService.isNewerVersion('0.10.0', '0.9.0'), isFalse);
    });

    test('段数不同：缺失段视为 0', () {
      expect(UpdateService.isNewerVersion('0.8', '0.8.1'), isTrue);
      expect(UpdateService.isNewerVersion('0.8.0', '0.8'), isFalse);
      expect(UpdateService.isNewerVersion('0.8', '0.8.0'), isFalse);
    });

    test('数值相同：正式版新于预发布版', () {
      expect(UpdateService.isNewerVersion('0.9.0-beta.1', '0.9.0'), isTrue);
      expect(UpdateService.isNewerVersion('0.9.0', '0.9.0-beta.1'), isFalse);
      expect(UpdateService.isNewerVersion('0.9.0-beta.1', '0.9.0-beta.2'),
          isFalse);
    });

    test('非法版本号 → false（不抛异常）', () {
      expect(UpdateService.isNewerVersion('abc', '0.9.0'), isFalse);
      expect(UpdateService.isNewerVersion('', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('1.0.0', ''), isFalse);
    });
  });

  group('parseRelease 解析', () {
    Map<String, dynamic> sampleRelease() => {
          'tag_name': 'v0.9.0',
          'body': '- 修复若干问题\n- 新增更新检查',
          'html_url': 'https://github.com/SakuraLoveSmile/AsmrDownloader/'
              'releases/tag/v0.9.0',
          'assets': [
            {
              'name': 'AsmrDownloader-v0.9.0-Windows.zip',
              'browser_download_url': 'https://fake.test/win.zip',
              'size': 12345,
            },
            {
              'name': 'AsmrDownloader-v0.9.0-macOS.zip',
              'browser_download_url': 'https://fake.test/mac.zip',
              'size': 67890,
            },
          ],
        };

    test('按平台后缀匹配 asset', () {
      final mac = UpdateService.parseRelease(sampleRelease(),
          assetSuffix: '-macOS.zip');
      expect(mac, isNotNull);
      expect(mac!.tagName, 'v0.9.0');
      expect(mac.version, '0.9.0');
      expect(mac.assetUrl, 'https://fake.test/mac.zip');
      expect(mac.assetSize, 67890);
      expect(mac.releaseNotes, contains('新增更新检查'));
      expect(mac.htmlUrl, contains('releases/tag/v0.9.0'));

      final win = UpdateService.parseRelease(sampleRelease(),
          assetSuffix: '-Windows.zip');
      expect(win!.assetUrl, 'https://fake.test/win.zip');
    });

    test('识别 SHA256SUMS asset 并记录下载地址', () {
      final release = sampleRelease()
        ..['assets'].add({
          'name': 'SHA256SUMS',
          'browser_download_url': 'https://fake.test/SHA256SUMS',
        });
      final mac =
          UpdateService.parseRelease(release, assetSuffix: '-macOS.zip');
      expect(mac!.checksumsUrl, 'https://fake.test/SHA256SUMS');
      // 未提供 SHA256SUMS 时为空串（下载时跳过校验）
      final noSums = UpdateService.parseRelease(sampleRelease(),
          assetSuffix: '-macOS.zip');
      expect(noSums!.checksumsUrl, '');
    });

    test('extractSha256For：从 sha256sum 文本提取指定文件哈希', () {
      const sums = '''
2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae  AsmrDownloader-v0.9.0-Windows.zip
68aa2e2ee5dff95e58c5b0c91f36d7c2f2e2e75d2ba0e6d3f0e7d0f8d0c0b0a1  AsmrDownloader-v0.9.0-macOS.zip
''';
      expect(
        UpdateService.extractSha256For(sums, 'AsmrDownloader-v0.9.0-macOS.zip'),
        '68aa2e2ee5dff95e58c5b0c91f36d7c2f2e2e75d2ba0e6d3f0e7d0f8d0c0b0a1',
      );
      expect(UpdateService.extractSha256For(sums, 'missing.zip'), '');
      // 哈希长度非法的行不应被采纳
      expect(
        UpdateService.extractSha256For('abc  pkg.zip', 'pkg.zip'),
        '',
      );
    });

    test('缺少匹配 asset / tag → null', () {
      final noMac = sampleRelease()..['assets'] = <Map<String, dynamic>>[];
      expect(
          UpdateService.parseRelease(noMac, assetSuffix: '-macOS.zip'), isNull);
      final noTag = sampleRelease()..remove('tag_name');
      expect(
          UpdateService.parseRelease(noTag, assetSuffix: '-macOS.zip'), isNull);
    });
  });

  group('checkForUpdate', () {
    // asset 后缀随平台；Linux CI 无该值，测试用 macOS 后缀保持自洽
    final suffix = UpdateService.platformAssetSuffix ?? '-macOS.zip';

    UpdateService buildService(String releaseJson) {
      return UpdateService(
        apiDio: Dio()
          ..httpClientAdapter = _FakeAdapter({
            'api.github.com': releaseJson,
          }),
      );
    }

    String releaseWithAsset(String tag) => json.encode({
          'tag_name': tag,
          'body': 'notes',
          'html_url': 'https://fake.test/release',
          'assets': [
            {
              'name': 'AsmrDownloader-$tag$suffix',
              'browser_download_url': 'https://fake.test/pkg.zip',
              'size': 100,
            },
          ],
        });

    test('发现新版本 → info 含版本与地址，响应体可缓存', () async {
      final svc = buildService(releaseWithAsset('v9.9.9'));
      final result = await svc.checkForUpdate('0.8.0');
      expect(result.info, isNotNull);
      expect(result.info!.version, '9.9.9');
      expect(result.info!.assetUrl, 'https://fake.test/pkg.zip');
      expect(result.releaseBody, contains('v9.9.9'));
    });

    test('Release 提供 SHA256SUMS → info 附带平台 zip 哈希', () async {
      final releaseJson = json.encode({
        'tag_name': 'v9.9.9',
        'body': 'notes',
        'html_url': 'https://fake.test/release',
        'assets': [
          {
            'name': 'AsmrDownloader-v9.9.9$suffix',
            'browser_download_url': 'https://fake.test/pkg.zip',
            'size': 100,
          },
          {
            'name': 'SHA256SUMS',
            'browser_download_url': 'https://fake.test/dl/SHA256SUMS',
          },
        ],
      });
      final sums = 'a' * 64 + '  pkg.zip\n';
      final svc = UpdateService(
        apiDio: Dio()
          ..httpClientAdapter = _FakeAdapter({
            'api.github.com': releaseJson,
            'SHA256SUMS': sums,
          }),
      );
      final result = await svc.checkForUpdate('0.0.1');
      expect(result.info, isNotNull);
      expect(result.info!.assetSha256, 'a' * 64);
    });

    test('已是最新 / 更低版本 → info 为 null', () async {
      final svc = buildService(releaseWithAsset('v0.8.0'));
      expect((await svc.checkForUpdate('0.8.0')).info, isNull);
      final older = buildService(releaseWithAsset('v0.7.0'));
      expect((await older.checkForUpdate('0.8.0')).info, isNull);
    });

    test('Release 缺当前平台 asset → info 为 null 不抛异常', () async {
      final svc = buildService(json.encode({
        'tag_name': 'v9.9.9',
        'assets': <Map<String, dynamic>>[],
      }));
      expect((await svc.checkForUpdate('0.8.0')).info, isNull);
    });

    test('网络失败（404）→ 抛 UpdateCheckException', () async {
      final svc = UpdateService(
        apiDio: Dio()..httpClientAdapter = _FakeAdapter(const {}),
      );
      await expectLater(
        svc.checkForUpdate('0.8.0'),
        throwsA(isA<UpdateCheckException>()),
      );
    });

    test('304（ETag 命中）→ 复用缓存响应体判定，不重新解析网络响应', () async {
      final body = releaseWithAsset('v9.9.9');
      final svc = UpdateService(
        apiDio: Dio()
          ..httpClientAdapter =
              _FakeAdapter({'api.github.com': body}, statusOverride: 304),
      );
      final result = await svc.checkForUpdate(
        '0.8.0',
        etag: 'W/"cached"',
        cachedReleaseBody: body,
      );
      expect(result.info, isNotNull);
      expect(result.info!.version, '9.9.9');
      // 304 无新响应：etag/body 沿用传入值
      expect(result.etag, 'W/"cached"');
      expect(result.releaseBody, body);
    });

    test('403 且配额耗尽 → 抛异常并提示速率限制', () async {
      final svc = UpdateService(
        apiDio: Dio()
          ..httpClientAdapter = _FakeAdapter({'api.github.com': '{}'},
              statusOverride: 403,
              responseHeaders: {'x-ratelimit-remaining': '0'}),
      );
      await expectLater(
        svc.checkForUpdate('0.8.0'),
        throwsA(isA<UpdateCheckException>()
            .having((e) => e.message, 'message', contains('速率限制'))),
      );
    });

    test('403 但配额未耗尽 → 提示拒绝访问而非限流', () async {
      final svc = UpdateService(
        apiDio: Dio()
          ..httpClientAdapter = _FakeAdapter({'api.github.com': '{}'},
              statusOverride: 403,
              responseHeaders: {'x-ratelimit-remaining': '59'}),
      );
      await expectLater(
        svc.checkForUpdate('0.8.0'),
        throwsA(isA<UpdateCheckException>()
            .having((e) => e.message, 'message', contains('403'))),
      );
    });

    test('配置 githubToken → API 请求携带 Bearer 认证头', () async {
      final adapter =
          _FakeAdapter({'api.github.com': releaseWithAsset('v9.9.9')});
      final svc = UpdateService(apiDio: Dio()..httpClientAdapter = adapter);
      svc.githubToken = ' ghp_test123 ';
      final result = await svc.checkForUpdate('0.8.0');
      expect(result.info, isNotNull);
      expect(adapter.lastHeaders?['authorization'], 'Bearer ghp_test123');
    });

    test('清除 githubToken → 不再携带认证头', () async {
      final adapter =
          _FakeAdapter({'api.github.com': releaseWithAsset('v9.9.9')});
      final svc = UpdateService(apiDio: Dio()..httpClientAdapter = adapter);
      svc.githubToken = 'ghp_test123';
      svc.githubToken = '';
      final result = await svc.checkForUpdate('0.8.0');
      expect(result.info, isNotNull);
      expect(adapter.lastHeaders?.containsKey('authorization'), isFalse);
    });

    test('Token 无效（401）→ 自动移除认证头匿名重试成功', () async {
      final adapter = _SequenceAdapter([
        // 与真实 GitHub 一致：401 body 为合法 JSON
        ResponseBody.fromString('{"message":"Bad credentials"}', 401),
        ResponseBody.fromString(releaseWithAsset('v9.9.9'), 200),
      ]);
      final svc = UpdateService(apiDio: Dio()..httpClientAdapter = adapter);
      svc.githubToken = 'ghp_invalid';
      final result = await svc.checkForUpdate('0.8.0');
      expect(result.info, isNotNull);
      expect(result.info!.version, '9.9.9');
      // 第一次带无效 token，第二次匿名重试
      expect(adapter.headersList[0]['authorization'], 'Bearer ghp_invalid');
      expect(adapter.headersList[1].containsKey('authorization'), isFalse);
    });

    test('连接失败 → 提示带底层原因（非笼统网络错误）', () async {
      final svc = UpdateService(
        apiDio: Dio()
          ..httpClientAdapter =
              _ThrowingAdapter(SocketException('Connection refused')),
      );
      await expectLater(
        svc.checkForUpdate('0.8.0'),
        throwsA(isA<UpdateCheckException>().having(
            (e) => e.message, 'message', contains('Connection refused'))),
      );
    });
  }, skip: supportedUpdatePlatform ? false : 'Windows/macOS only');

  group('evaluateRelease 缓存判定', () {
    // asset 后缀随平台；Linux CI 无该值，测试用 macOS 后缀保持自洽
    final suffix = UpdateService.platformAssetSuffix ?? '-macOS.zip';

    test('缓存响应体 → 判定新版本', () {
      final body = json.encode({
        'tag_name': 'v9.9.9',
        'assets': [
          {
            'name': 'AsmrDownloader-v9.9.9$suffix',
            'browser_download_url': 'https://fake.test/win.zip',
          },
        ],
      });
      final info = UpdateService.evaluateRelease(body, '0.8.0');
      expect(info, isNotNull);
      expect(info!.version, '9.9.9');
    });

    test('当前版本已起上缓存 → null（升级后不再提示旧结论）', () {
      final body = json.encode({
        'tag_name': 'v0.9.0',
        'assets': [
          {
            'name': 'AsmrDownloader-v0.9.0$suffix',
            'browser_download_url': 'https://fake.test/win.zip',
          },
        ],
      });
      expect(UpdateService.evaluateRelease(body, '0.9.0'), isNull);
    });

    test('空/非法响应体 → null 不抛异常', () {
      expect(UpdateService.evaluateRelease(null, '0.8.0'), isNull);
      expect(UpdateService.evaluateRelease('', '0.8.0'), isNull);
      expect(UpdateService.evaluateRelease('not json', '0.8.0'), isNull);
    });
  }, skip: supportedUpdatePlatform ? false : 'Windows/macOS only');

  group('downloadUpdate', () {
    test('下载成功且大小一致 → 返回 zip 路径', () async {
      final bytes = utf8.encode('fake zip content');
      final svc = UpdateService(downloader: _FakeDownloader(bytes));
      const info = UpdateInfo(
        tagName: 'v9.9.9',
        version: '9.9.9',
        releaseNotes: '',
        assetUrl: 'https://fake.test/pkg.zip',
        assetSize: 16,
        htmlUrl: '',
      );
      var progressCalled = false;
      final path = await svc.downloadUpdate(
        info,
        onProgress: (r, t) => progressCalled = true,
      );
      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue);
      expect(progressCalled, isTrue);
      await File(path).parent.delete(recursive: true);
    });

    test('大小不符 → 删除文件并返回 null', () async {
      final bytes = utf8.encode('short');
      final svc = UpdateService(downloader: _FakeDownloader(bytes));
      const info = UpdateInfo(
        tagName: 'v9.9.9',
        version: '9.9.9',
        releaseNotes: '',
        assetUrl: 'https://fake.test/pkg.zip',
        assetSize: 99999,
        htmlUrl: '',
      );
      final path = await svc.downloadUpdate(info);
      expect(path, isNull);
    });

    test('SHA-256 一致 → 校验通过返回 zip 路径', () async {
      final bytes = utf8.encode('fake zip content');
      final expected = sha256Of(bytes);
      final svc = UpdateService(downloader: _FakeDownloader(bytes));
      final info = const UpdateInfo(
        tagName: 'v9.9.9',
        version: '9.9.9',
        releaseNotes: '',
        assetUrl: 'https://fake.test/pkg.zip',
        assetSize: 16,
        htmlUrl: '',
      ).copyWith(assetSha256: expected);
      final path = await svc.downloadUpdate(info);
      expect(path, isNotNull);
      await File(path!).parent.delete(recursive: true);
    });

    test('SHA-256 不符 → 删除文件并返回 null', () async {
      final bytes = utf8.encode('fake zip content');
      final svc = UpdateService(downloader: _FakeDownloader(bytes));
      final info = const UpdateInfo(
        tagName: 'v9.9.9',
        version: '9.9.9',
        releaseNotes: '',
        assetUrl: 'https://fake.test/pkg.zip',
        assetSize: 16,
        htmlUrl: '',
      ).copyWith(assetSha256: '0' * 64);
      final path = await svc.downloadUpdate(info);
      expect(path, isNull);
      // 损坏文件已被删除
      expect(
        Directory(p.join(Directory.systemTemp.path, 'asmr_update_dl'))
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.zip')),
        isEmpty,
      );
    });

    test('下载失败 → null', () async {
      final svc = UpdateService(downloader: _FakeDownloader(null));
      const info = UpdateInfo(
        tagName: 'v9.9.9',
        version: '9.9.9',
        releaseNotes: '',
        assetUrl: 'https://fake.test/pkg.zip',
        assetSize: 100,
        htmlUrl: '',
      );
      expect(await svc.downloadUpdate(info), isNull);
    });
  });

  group('更新脚本生成', () {
    test('Windows VBS 脚本：WMI 等 PID → 隐藏 xcopy → 重启 → 自删', () {
      final script = UpdateService.buildWindowsVbsScript(
          4242, r'C:\tmp\staging', r'C:\app', 'AsmrDownloader.exe');
      expect(script, contains('WScript.Arguments(0)'));
      expect(script, contains('WScript.Arguments(1)'));
      expect(script, contains('WScript.Arguments(2)'));
      expect(script, contains('WScript.Arguments(3)'));
      expect(script, contains('Win32_Process'));
      expect(script, contains('WScript.Sleep 1000'));
      expect(script, contains('shell.Run("cmd.exe /c xcopy'));
      expect(script, contains(', 0, True'));
      expect(script, contains('fso.CopyFile installExe, exeBackup, True'));
      expect(script, contains('xcopyResult = shell.Run('));
      expect(script, contains('If xcopyResult <> 0 Then'));
      // 失败回滚：从备份恢复主程序且不启动新版本
      expect(script, contains('fso.CopyFile exeBackup, installExe, True'));
      expect(script, contains('WScript.Quit 1'));
      expect(script, contains('shell.Run Quote(installExe), 1, False'));
      expect(script, contains('fso.DeleteFile WScript.ScriptFullName'));
      expect(script, isNot(contains('ping')));
      expect(script, isNot(contains('tasklist')));
    });

    test('macOS 脚本：等 PID 退出 → 旧 .app 备份 → 移入新 .app → open；失败回滚', () {
      final script = UpdateService.buildMacScript(
          4242, '/tmp/staging/AsmrDownloader.app', '/app/AsmrDownloader.app');
      expect(script, contains('PID="4242"'));
      expect(script, contains('kill -0 "\$PID"'));
      // 旧 .app 先改名备份，不再直接 rm -rf 删除
      expect(script, contains('mv "\$OLD_APP" "\$BACKUP"'));
      expect(script, contains('mv "\$NEW_APP"'));
      expect(script, contains('open "\$OLD_APP"'));
      // 成功后清理备份
      expect(script, contains('rm -rf "\$BACKUP"'));
      // 移入失败时把备份改回原名并重启旧版
      expect(script, contains('mv "\$BACKUP" "\$OLD_APP"'));
      expect(script, contains('rm -f "\$0"'));
    });
  });

  test('非 release 构建禁止 applyUpdate', () async {
    final svc = UpdateService();
    expect(await svc.applyUpdate('/nonexistent/pkg.zip'), isFalse);
  });

  group('prepareAndLaunchUpdate 安装编排', () {
    test('解压 → 生成平台脚本 → 启动脚本 → 退出应用', () async {
      final tmp = Directory.systemTemp.createTempSync('upd_apply');
      final zipPath = p.join(tmp.path, 'pkg.zip');
      File(zipPath).writeAsStringSync('fake');

      final launched = <(String, List<String>)>[];
      var exitCode = -1;
      final svc = UpdateService(
        extractor: (zip, dest) async {
          // 模拟解压产物：Windows 平铺主 exe / macOS 根目录含完整 .app
          if (Platform.isWindows) {
            File(p.join(dest, p.basename(Platform.resolvedExecutable)))
                .writeAsStringSync('x');
          } else {
            Directory(p.join(dest, 'AsmrDownloader.app', 'Contents', 'MacOS'))
                .createSync(recursive: true);
          }
          return true;
        },
        scriptLauncher: (exec, args) async {
          launched.add((exec, args));
          return true;
        },
        exitFn: (code) => exitCode = code,
      );
      final ok = await svc.prepareAndLaunchUpdate(zipPath);
      expect(ok, isTrue);
      expect(launched, hasLength(1));
      final scriptPath = Platform.isWindows
          ? launched.single.$2.first // wscript.exe <script> <args>
          : launched.single.$2.single; // /bin/sh <script>
      expect(
          launched.single.$1, Platform.isWindows ? 'wscript.exe' : '/bin/sh');
      final script = File(scriptPath).readAsStringSync();
      if (Platform.isMacOS) {
        // 旧 .app = 当前进程可执行文件上溯 3 级
        final oldApp =
            p.dirname(p.dirname(p.dirname(Platform.resolvedExecutable)));
        expect(script, contains('OLD_APP="$oldApp"'));
        expect(
            script,
            contains('NEW_APP="'
                '${p.join(tmp.path, 'staging', 'AsmrDownloader.app')}"'));
      } else if (Platform.isWindows) {
        final installDir = p.dirname(Platform.resolvedExecutable);
        expect(launched.single.$2, hasLength(5));
        expect(launched.single.$2[1], '$pid');
        expect(launched.single.$2[2], p.join(tmp.path, 'staging'));
        expect(launched.single.$2[3], installDir);
        expect(launched.single.$2[4], p.basename(Platform.resolvedExecutable));
        expect(script, contains('WScript.Arguments'));
        expect(script, contains('xcopy'));
      }
      expect(exitCode, 0);
      File(scriptPath).deleteSync();
      tmp.deleteSync(recursive: true);
    }, skip: supportedUpdatePlatform ? false : 'Windows/macOS only');

    test('解压失败 → 返回 false 且不启动脚本、不退出', () async {
      final tmp = Directory.systemTemp.createTempSync('upd_apply_fail');
      final zipPath = p.join(tmp.path, 'pkg.zip');
      File(zipPath).writeAsStringSync('fake');
      final launched = <String>[];
      var exited = false;
      final svc = UpdateService(
        extractor: (zip, dest) async => false,
        scriptLauncher: (exec, args) async {
          launched.add(exec);
          return true;
        },
        exitFn: (code) => exited = true,
      );
      expect(await svc.prepareAndLaunchUpdate(zipPath), isFalse);
      expect(launched, isEmpty);
      expect(exited, isFalse);
      tmp.deleteSync(recursive: true);
    });

    test('解压产物异常（macOS 缺 .app / Windows 空目录）→ false', () async {
      final tmp = Directory.systemTemp.createTempSync('upd_apply_bad');
      final zipPath = p.join(tmp.path, 'pkg.zip');
      File(zipPath).writeAsStringSync('fake');
      final svc = UpdateService(
        // 解压成功但 staging 为空/无 .app
        extractor: (zip, dest) async => true,
        scriptLauncher: (exec, args) async => true,
        exitFn: (code) {},
      );
      expect(await svc.prepareAndLaunchUpdate(zipPath), isFalse);
      tmp.deleteSync(recursive: true);
    });
  });
}

/// 按 URL 关键字返回预置响应的假 Dio 适配器。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responses, {this.statusOverride, this.responseHeaders});

  /// key = URL 包含的子串，value = 响应体
  final Map<String, String> responses;

  /// 非 null 时强制返回该状态码（模拟 304/403 等）
  final int? statusOverride;

  /// 附加响应头（如 x-ratelimit-remaining）
  final Map<String, String>? responseHeaders;

  /// 最近一次请求的头（key 转小写；供认证头断言）
  Map<String, String>? lastHeaders;

  @override
  void close({bool force = true}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    lastHeaders = {
      for (final e in options.headers.entries)
        e.key.toLowerCase(): '${e.value}',
    };
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

/// 假下载器：写入预置字节（null = 模拟下载失败）。
class _FakeDownloader extends ChunkDownloader {
  _FakeDownloader(this.content);

  final List<int>? content;

  @override
  Future<bool> download({
    required String url,
    required String savePath,
    int fileSize = 0,
    int threadCount = 4,
    CancelToken? cancelToken,
    void Function(int received, int total)? onProgress,
  }) async {
    final bytes = content;
    if (bytes == null) return false;
    File(savePath)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    onProgress?.call(bytes.length, bytes.length);
    return true;
  }
}

/// 按顺序返回预置响应的适配器（记录每次请求头，供认证降级断言）。
class _SequenceAdapter implements HttpClientAdapter {
  _SequenceAdapter(this.responses);

  final List<ResponseBody> responses;
  final List<Map<String, String>> headersList = [];
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
    final resp =
        responses[_index < responses.length ? _index : responses.length - 1];
    _index++;
    // 与真实 GitHub API 一致：JSON 响应带 content-type
    resp.headers[Headers.contentTypeHeader] = [Headers.jsonContentType];
    return resp;
  }
}

/// 直接抛底层异常的适配器（模拟连接失败/超时等）。
class _ThrowingAdapter implements HttpClientAdapter {
  _ThrowingAdapter(this.error);

  final Object error;

  @override
  void close({bool force = true}) {}

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    throw error;
  }
}
