import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:asmr_downloader/services/transcribe/chicken_rice_config.dart';
import 'package:asmr_downloader/services/transcribe/chicken_rice_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ChickenRiceConfig', () {
    test('默认配置为 translate + lrc，后缀与缺口检测对齐', () {
      const cfg = ChickenRiceConfig();
      expect(cfg.task, 'translate');
      expect(cfg.subFormats, 'lrc');
      expect(cfg.device, 'auto');
      // 与 SubtitleGapDetector.kAudioExtensions 一致（含视频格式）
      for (final ext in const [
        'wav',
        'flac',
        'mp3',
        'm4a',
        'aac',
        'ogg',
        'wma',
        'mp4',
        'mkv',
        'avi',
        'mov',
        'webm',
        'flv',
        'wmv',
      ]) {
        expect(cfg.audioSuffixes.split(','), contains(ext));
      }
    });

    test('isConfigured 判断脚本是否已设置', () {
      expect(const ChickenRiceConfig().isConfigured, false);
      expect(const ChickenRiceConfig(scriptPath: '/x/infer.exe').isConfigured,
          true);
    });

    test('isBat 按扩展名识别 bat/cmd', () {
      expect(const ChickenRiceConfig(scriptPath: 'C:\\t\\run.bat').isBat, true);
      expect(const ChickenRiceConfig(scriptPath: 'C:\\t\\run.cmd').isBat, true);
      expect(
          const ChickenRiceConfig(scriptPath: 'C:\\t\\infer.exe').isBat, false);
      expect(
          const ChickenRiceConfig(scriptPath: 'C:\\t\\infer.EXE').isBat, false);
    });
  });

  group('probeScript', () {
    test('未配置返回错误', () {
      expect(ChickenRiceService(const ChickenRiceConfig()).probeScript(),
          isNotNull);
    });

    test('文件不存在返回错误', () {
      expect(
          ChickenRiceService(
                  const ChickenRiceConfig(scriptPath: '/nope/run.bat'))
              .probeScript(),
          contains('不存在'));
    });

    test('不支持的扩展名返回错误', () {
      final tmp = createTempScript('script.txt');
      expect(
          ChickenRiceService(ChickenRiceConfig(scriptPath: tmp.path))
              .probeScript(),
          contains('不支持'));
      tmp.deleteSync();
    });

    test('bat/exe 存在时：Windows 返回 null，非 Windows 提示仅支持 Windows', () {
      final bat = createTempScript('run.bat');
      final probe = ChickenRiceService(ChickenRiceConfig(scriptPath: bat.path))
          .probeScript();
      if (Platform.isWindows) {
        expect(probe, isNull);
      } else {
        expect(probe, contains('仅支持 Windows'));
      }
      bat.deleteSync();

      final exe = createTempScript('infer.exe');
      final probeExe =
          ChickenRiceService(ChickenRiceConfig(scriptPath: exe.path))
              .probeScript();
      if (Platform.isWindows) {
        expect(probeExe, isNull);
      } else {
        expect(probeExe, contains('仅支持 Windows'));
      }
      exe.deleteSync();
    });
  });

  group('buildCommand', () {
    test('exe 模式：拼接基础参数 + base_dirs', () {
      const cfg = ChickenRiceConfig(scriptPath: 'C:\\t\\infer.exe');
      final svc = ChickenRiceService(cfg);
      final cmd = svc.buildCommand(['D:\\asmr\\RJ1']);
      expect(cmd.first, 'C:\\t\\infer.exe');
      expect(cmd, contains('--device=auto'));
      expect(cmd, contains('--task=translate'));
      expect(cmd, contains('--sub_formats=lrc'));
      expect(
          cmd,
          contains(
              '--audio_suffixes=wav,flac,mp3,m4a,aac,ogg,wma,mp4,mkv,avi,mov,webm,flv,wmv'));
      expect(cmd.last, 'D:\\asmr\\RJ1');
    });

    test('exe 模式：task=transcribe + overwrite 时追加参数', () {
      const cfg = ChickenRiceConfig(
        scriptPath: '/opt/infer',
        task: 'transcribe',
        overwrite: true,
      );
      final cmd = ChickenRiceService(cfg).buildCommand(['dir']);
      expect(cmd, contains('--task=transcribe'));
      expect(cmd, contains('--overwrite'));
    });

    test('exe 模式：多目录各自作为独立参数（支持空格路径）', () {
      const cfg = ChickenRiceConfig(scriptPath: 'C:\\t\\infer.exe');
      final cmd = ChickenRiceService(cfg).buildCommand(['D:\\a 1', 'D:\\b 2']);
      expect(cmd.sublist(cmd.length - 2), ['D:\\a 1', 'D:\\b 2']);
      expect(cmd, isNot(contains('D:\\a 1 D:\\b 2')));
    });

    test('bat 模式（首选）：解析 bat 直调 infer.exe（绕开 cmd，路径无损）', () {
      final bat = createBatScript(_officialBatTemplate);
      // bat 同目录放一个 infer.exe 才会走直调路径（existsSync 校验）
      final exe = File('${bat.parent.path}${p.separator}infer.exe')
        ..writeAsStringSync('x');
      final cfg = ChickenRiceConfig(scriptPath: bat.path);
      final cmd = ChickenRiceService(cfg).buildCommand(['D:\\asmr\\RJ1']);
      // 不经 cmd.exe，直接调 exe（Dart CreateProcessW 传参，UTF-16 无损）
      expect(cmd.first, endsWith('infer.exe'));
      expect(cmd, contains('--device=cuda'));
      expect(cmd, contains('--task=translate'));
      // 输出格式由应用配置统一（默认只出 lrc）：覆盖 bat 自带的 srt,vtt,lrc
      expect(cmd, contains('--sub_formats=lrc'));
      expect(cmd.where((a) => a.startsWith('--sub_formats')).length, 1);
      expect(cmd, isNot(contains('--sub_formats=srt,vtt,lrc')));
      expect(cmd.last, 'D:\\asmr\\RJ1');
      exe.deleteSync();
      bat.deleteSync();
    });

    test('bat 模式（首选）：多目录 + overwrite 时直调参数正确（overwrite 在目录前）', () {
      final bat = createBatScript(_officialBatTemplate);
      final exe = File('${bat.parent.path}${p.separator}infer.exe')
        ..writeAsStringSync('x');
      final cfg = ChickenRiceConfig(scriptPath: bat.path, overwrite: true);
      final cmd = ChickenRiceService(cfg).buildCommand(['D:\\a', 'D:\\b']);
      // --overwrite 在目录前，否则会被 base_dirs(REMAINDER) 吞掉
      final ov = cmd.indexOf('--overwrite');
      expect(ov, greaterThan(0));
      expect(cmd.sublist(ov + 1), ['D:\\a', 'D:\\b']);
      exe.deleteSync();
      bat.deleteSync();
    });

    test('bat 模式：exe 不存在时回退 UTF-8 wrapper 真调用原 bat', () {
      final bat = createBatScript(_officialBatTemplate);
      // 目录内无 infer.exe → 直调不可用 → 回退 wrapper
      final cfg = ChickenRiceConfig(scriptPath: bat.path);
      final cmd = ChickenRiceService(cfg).buildCommand(['D:\\asmr\\RJ1']);
      // cmd /d /c <wrapper.bat>：wrapper 是纯 ASCII 路径，不受代码页转码影响
      expect(cmd.take(3), ['cmd.exe', '/d', '/c']);
      final wrapper = File(cmd.last);
      expect(wrapper.existsSync(), isTrue);
      final content = wrapper.readAsStringSync();
      // wrapper 以 UTF-8 BOM 开头（Win11 24H2+ cmd 原生 UTF-8 解析）；
      // readAsStringSync 会吞掉 BOM，故用原始字节校验
      expect(wrapper.readAsBytesSync().sublist(0, 3), [0xEF, 0xBB, 0xBF]);
      // wrapper 用 chcp 65001 + UTF-8 写路径，随后真调用原 bat
      expect(content, contains('chcp 65001 >nul'));
      expect(content, contains('call "${bat.path}"'));
      expect(content, contains('"D:\\asmr\\RJ1"'));
      // 不带任务/设备参数（由原 bat 决定）
      expect(content, isNot(contains('--device=')));
      wrapper.deleteSync();
      bat.deleteSync();
    });

    test('bat 模式：wrapper 多目录 + overwrite 内容正确（overwrite 在目录前）', () {
      final bat = createBatScript('@echo off\necho no infer here\npause');
      final cfg = ChickenRiceConfig(scriptPath: bat.path, overwrite: true);
      final cmd = ChickenRiceService(cfg).buildCommand(['D:\\a', 'D:\\b']);
      final content = File(cmd.last).readAsStringSync();
      // --overwrite 在目录前，否则会被 base_dirs(REMAINDER) 吞掉
      final callLine =
          content.split('\n').firstWhere((l) => l.startsWith('call '));
      expect(callLine, contains(' --overwrite "D:\\a" "D:\\b"'));
      File(cmd.last).deleteSync();
      bat.deleteSync();
    });

    test('bat 模式：wrapper 中转义 %（避免 cmd 变量展开）', () {
      final dir = Directory.systemTemp.createTempSync('cr_pct');
      final bat = File(p.join(dir.path, 'run(100%).bat'))
        ..writeAsStringSync('x');
      final cfg = ChickenRiceConfig(scriptPath: bat.path);
      final cmd = ChickenRiceService(cfg).buildCommand(['D:\\50% 目录']);
      final content = File(cmd.last).readAsStringSync();
      expect(content, contains('call "${bat.path.replaceAll('%', '%%')}"'));
      expect(content, contains('"${'D:\\50% 目录'.replaceAll('%', '%%')}"'));
      File(cmd.last).deleteSync();
      dir.deleteSync(recursive: true);
    });

    test('bat 模式：解析失败（无 infer.exe）且 wrapper 失败时回退 cmd call', () {
      final bat = createBatScript('@echo off\necho no infer here\npause');
      final svc = ChickenRiceService(
        ChickenRiceConfig(scriptPath: bat.path),
        tempDir: Directory(p.join(Directory.systemTemp.path,
            'no_such_dir_${DateTime.now().millisecondsSinceEpoch}')),
      );
      final cmd = svc.buildCommand(['D:\\dir']);
      expect(cmd.take(4), ['cmd.exe', '/d', '/c', 'call']);
      expect(cmd[4], bat.path);
      expect(cmd.last, 'D:\\dir');
      bat.deleteSync();
    });
  });

  group('run', () {
    test('脚本未配置时返回 false 且不调用进程', () async {
      var started = false;
      final svc = ChickenRiceService(
        const ChickenRiceConfig(),
        skipPlatformCheck: true,
        runner: _FakeRunner((cmd, env) {
          started = true;
          return _completedHandle();
        }),
      );
      final result = await svc.run(dirs: ['/some/dir']);
      expect(result.success, false);
      expect(started, false);
    });

    test('脚本不存在时返回 false', () async {
      var started = false;
      final svc = ChickenRiceService(
        const ChickenRiceConfig(scriptPath: '/nope/run.bat'),
        skipPlatformCheck: true,
        runner: _FakeRunner((cmd, env) {
          started = true;
          return _completedHandle();
        }),
      );
      final result = await svc.run(dirs: ['/some/dir']);
      expect(result.success, false);
      expect(started, false);
    });

    test('非 Windows 平台 probe 拦截（不启动进程）', () async {
      if (Platform.isWindows) return; // 仅非 Windows 断言
      var started = false;
      final tmp = createTempScript('infer.bat');
      final svc = ChickenRiceService(
        ChickenRiceConfig(scriptPath: tmp.path),
        runner: _FakeRunner((cmd, env) {
          started = true;
          return _completedHandle();
        }),
      );
      final result = await svc.run(dirs: ['/some/dir']);
      expect(result.success, false);
      expect(started, false);
      expect(result.error, contains('仅支持 Windows'));
      tmp.deleteSync();
    });

    test('退出码 0 返回 success，并透传环境变量', () async {
      // 需要一个真实存在的临时 bat 作为脚本，probe 才通过
      final tmp = createTempScript('infer.bat');
      Map<String, String>? capturedEnv;
      final svc = ChickenRiceService(
        ChickenRiceConfig(scriptPath: tmp.path),
        skipPlatformCheck: true,
        runner: _FakeRunner((cmd, env) {
          capturedEnv = env;
          return _completedHandle();
        }),
      );
      final result = await svc.run(dirs: ['/some/dir']);
      expect(result.success, true);
      expect(result.exitCode, 0);
      expect(capturedEnv, isNotNull);
      expect(capturedEnv!['PYTHONUTF8'], '1');
      tmp.deleteSync();
    });

    test('非 0 退出码返回 false 并把 stdout 进度回调传递', () async {
      final tmp = createTempScript('infer.bat');
      final received = <int>[];
      final svc = ChickenRiceService(
        ChickenRiceConfig(scriptPath: tmp.path),
        skipPlatformCheck: true,
        runner: _FakeRunner((cmd, env) => _FakeHandle(
              stdoutLines: ['VAD进度：3/120 块（2.5%） on cuda'],
              exitCode: 1,
            )),
      );
      final result = await svc.run(
        dirs: ['/d'],
        onProgress: (p) => received.add(p.done),
      );
      expect(result.success, false);
      expect(received, [3]);
      tmp.deleteSync();
    });

    test('stderr 文件级进度被解析并带当前文件名', () async {
      final tmp = createTempScript('infer.bat');
      final received = <TranscribeProgress>[];
      final svc = ChickenRiceService(
        ChickenRiceConfig(scriptPath: tmp.path),
        skipPlatformCheck: true,
        runner: _FakeRunner((cmd, env) => _FakeHandle(
              stderrLines: ['正在处理（translate，2/5）：D:\\asmr\\RJ1\\e01.wav'],
            )),
      );
      final result = await svc.run(
        dirs: ['/d'],
        onProgress: (p) => received.add(p),
      );
      expect(result.success, true);
      expect(received, hasLength(1));
      expect(received.first.done, 2);
      expect(received.first.total, 5);
      expect(received.first.currentFile, 'e01.wav');
      tmp.deleteSync();
    });

    test('stderr 英文文件级进度同样被解析', () async {
      final tmp = createTempScript('infer.bat');
      final received = <TranscribeProgress>[];
      final svc = ChickenRiceService(
        ChickenRiceConfig(scriptPath: tmp.path),
        skipPlatformCheck: true,
        runner: _FakeRunner((cmd, env) => _FakeHandle(
              stderrLines: ['Processing (translate) (3/8): C:\\x\\y.mp3'],
            )),
      );
      final result = await svc.run(
        dirs: ['/d'],
        onProgress: (p) => received.add(p),
      );
      expect(result.success, true);
      expect(received.first.done, 3);
      expect(received.first.total, 8);
      expect(received.first.currentFile, 'y.mp3');
      tmp.deleteSync();
    });

    test('文件级进度后 VAD 不覆盖总进度，只更新当前文件子进度', () async {
      final tmp = createTempScript('infer.bat');
      final received = <TranscribeProgress>[];
      final svc = ChickenRiceService(
        ChickenRiceConfig(scriptPath: tmp.path),
        skipPlatformCheck: true,
        runner: _FakeRunner((cmd, env) => _FakeHandle(
              stderrLines: [
                '正在处理（translate，1/8）：D:\\asmr\\RJ1\\e01.wav',
                'VAD进度：45/100 块（45%）',
              ],
            )),
      );
      final result = await svc.run(
        dirs: ['/d'],
        onProgress: received.add,
      );
      expect(result.success, isTrue);
      expect(received, hasLength(2));
      expect(received.last.done, 1);
      expect(received.last.total, 8);
      expect(received.last.currentFile, 'e01.wav');
      expect(received.last.subDone, 45);
      expect(received.last.subTotal, 100);
      tmp.deleteSync();
    });

    test('非 VAD 比例文本不会触发临时进度', () async {
      final tmp = createTempScript('infer.bat');
      final received = <TranscribeProgress>[];
      final svc = ChickenRiceService(
        ChickenRiceConfig(scriptPath: tmp.path),
        skipPlatformCheck: true,
        runner: _FakeRunner((cmd, env) => _FakeHandle(
              stdoutLines: ['日期 2026/08/17', '下载比例 1/2'],
            )),
      );
      await svc.run(dirs: ['/d'], onProgress: received.add);
      expect(received, isEmpty);
      tmp.deleteSync();
    });

    test('解析处理文件数（找到 N 个文件待处理）', () async {
      final tmp = createTempScript('infer.bat');
      final svc = ChickenRiceService(
        ChickenRiceConfig(scriptPath: tmp.path),
        skipPlatformCheck: true,
        runner: _FakeRunner((cmd, env) => _FakeHandle(
              stderrLines: ['找到 3 个文件待处理'],
            )),
      );
      final result = await svc.run(dirs: ['/d']);
      expect(result.success, true);
      expect(result.filesProcessed, 3);
      tmp.deleteSync();
    });

    test('stdout/stderr 行经 onOutput 实时转发（供 UI 日志展示）', () async {
      final tmp = createTempScript('infer.bat');
      final lines = <String>[];
      final svc = ChickenRiceService(
        ChickenRiceConfig(scriptPath: tmp.path),
        skipPlatformCheck: true,
        runner: _FakeRunner((cmd, env) => _FakeHandle(
              stdoutLines: ['⚠️  重要声明 / IMPORTANT NOTICE', ''],
              stderrLines: ['正在加载模型…', '找到 2 个文件待处理'],
              // 真实进程流一定先于退出码结束；fake 里稍延迟避免竞态
              exitCodeFuture:
                  Future.delayed(const Duration(milliseconds: 10), () => 0),
            )),
      );
      final result = await svc.run(dirs: ['/d'], onOutput: lines.add);
      expect(result.success, true);
      // 非空行逐行转发，空行不转发
      expect(lines, [
        '⚠️  重要声明 / IMPORTANT NOTICE',
        '正在加载模型…',
        '找到 2 个文件待处理',
      ]);
      tmp.deleteSync();
    });

    test('未找到要处理的文件 → filesProcessed=0（假成功检测）', () async {
      final tmp = createTempScript('infer.bat');
      final svc = ChickenRiceService(
        ChickenRiceConfig(scriptPath: tmp.path),
        skipPlatformCheck: true,
        runner: _FakeRunner((cmd, env) => _FakeHandle(
              stderrLines: ['未找到要处理的文件'],
            )),
      );
      final result = await svc.run(dirs: ['/d']);
      expect(result.success, true);
      expect(result.filesProcessed, 0);
      tmp.deleteSync();
    });

    test('请求取消时 kill 进程并返回 false', () async {
      final tmp = createTempScript('infer.bat');
      var killed = false;
      // exitCode 在 kill 之后才完成，模拟真实进程被终止的时序
      final exitCompleter = Completer<int>();
      final svc = ChickenRiceService(
        ChickenRiceConfig(scriptPath: tmp.path),
        skipPlatformCheck: true,
        runner: _FakeRunner((cmd, env) => _FakeHandle(
              stdoutLines: const [],
              exitCodeFuture: exitCompleter.future,
              killCallback: () {
                killed = true;
                exitCompleter.complete(130); // SIGINT
              },
            )),
      );
      final result = await svc.run(
        dirs: ['/d'],
        isCancelled: () => true,
      );
      expect(result.success, false);
      expect(killed, true);
      tmp.deleteSync();
    });
  });
}

/// 官方 release bat 的结构模板（UTF-8）。
const String _officialBatTemplate = '''@echo off
chcp 65001
set cpath=%~dp0
set cpath=%cpath:~0,-1%
if "%~1"=="" goto prompt_input
"%cpath%\\infer.exe" --audio_suffixes="mp3,wav,flac,m4a,aac,ogg,wma,mp4,mkv,avi,mov,webm,flv,wmv" --sub_formats="srt,vtt,lrc" --device="cuda" --task="translate" %*
goto end

:prompt_input
echo 请将音视频文件拖到此窗口，然后按回车:
set "input_files="
set /p "input_files="
if defined input_files goto run_input
goto no_input

:run_input
"%cpath%\\infer.exe" --audio_suffixes="mp3,wav,flac,m4a,aac,ogg,wma,mp4,mkv,avi,mov,webm,flv,wmv" --sub_formats="srt,vtt,lrc" --device="cuda" --task="translate" %input_files%
goto end

:no_input
echo 未提供输入文件。

:end
pause
''';

/// 创建内容为 [content]（UTF-8）的临时 bat 文件。
File createBatScript(String content) {
  final dir = Directory.systemTemp.createTempSync('cr_bat');
  final f = File(p.join(dir.path, '运行(翻译)(GPU).bat'));
  f.writeAsStringSync(content, encoding: utf8);
  return f;
}

File createTempScript(String name) {
  final dir = Directory.systemTemp.createTempSync('cr_test');
  final f = File('${dir.path}/$name');
  f.writeAsStringSync('x');
  return f;
}

ProcessHandle _completedHandle() =>
    _FakeHandle(stdoutLines: const [], exitCode: 0);

class _FakeRunner implements ProcessRunner {
  final ProcessHandle Function(
      List<String> command, Map<String, String>? environment) onStart;

  _FakeRunner(this.onStart);

  @override
  Future<ProcessHandle> start(List<String> command,
      {String? workingDirectory, Map<String, String>? environment}) {
    return Future.value(onStart(command, environment));
  }
}

class _FakeHandle implements ProcessHandle {
  final int _exitCode;
  final Future<int>? _exitCodeFuture;
  final void Function()? killCallback;
  final StreamController<String> _out = StreamController<String>();
  final StreamController<String> _err = StreamController<String>();

  _FakeHandle({
    List<String> stdoutLines = const [],
    List<String> stderrLines = const [],
    int exitCode = 0,
    this.killCallback,
    Future<int>? exitCodeFuture,
  })  : _exitCode = exitCode,
        _exitCodeFuture = exitCodeFuture {
    for (final l in stdoutLines) {
      _out.add(l);
    }
    for (final l in stderrLines) {
      _err.add(l);
    }
    _out.close();
    _err.close();
  }

  @override
  Stream<String> get stdout => _out.stream;
  @override
  Stream<String> get stderr => _err.stream;
  @override
  Future<int> get exitCode => _exitCodeFuture ?? Future.value(_exitCode);
  @override
  void kill() => killCallback?.call();
}
