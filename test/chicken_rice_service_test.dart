import 'dart:async';
import 'dart:io';

import 'package:asmr_downloader/services/transcribe/chicken_rice_config.dart';
import 'package:asmr_downloader/services/transcribe/chicken_rice_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChickenRiceConfig', () {
    test('默认配置为 translate + lrc，后缀与缺口检测对齐', () {
      const cfg = ChickenRiceConfig();
      expect(cfg.task, 'translate');
      expect(cfg.subFormats, 'lrc');
      expect(cfg.device, 'auto');
      // 与 SubtitleGapDetector.kAudioExtensions 一致（含视频格式）
      for (final ext in const [
        'wav', 'flac', 'mp3', 'm4a', 'aac', 'ogg', 'wma',
        'mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'wmv',
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
      expect(const ChickenRiceConfig(scriptPath: 'C:\\t\\infer.exe').isBat,
          false);
      expect(const ChickenRiceConfig(scriptPath: 'C:\\t\\infer.EXE').isBat,
          false);
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
      expect(cmd, contains(
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

    test('bat 模式：经 cmd /c call 调用，只传目录，不带任务/设备参数', () {
      const cfg = ChickenRiceConfig(scriptPath: 'C:\\t\\运行(翻译)(GPU).bat');
      final cmd = ChickenRiceService(cfg).buildCommand(['D:\\asmr\\RJ1']);
      expect(cmd.take(4), ['cmd.exe', '/d', '/c', 'call']);
      expect(cmd[4], 'C:\\t\\运行(翻译)(GPU).bat');
      expect(cmd[5], 'D:\\asmr\\RJ1');
      expect(cmd.length, 6);
      expect(cmd.any((a) => a.startsWith('--task')), isFalse);
      expect(cmd.any((a) => a.startsWith('--device')), isFalse);
      expect(cmd.any((a) => a.startsWith('--sub_formats')), isFalse);
    });

    test('bat 模式：overwrite 必须放在目录之前（argparse REMAINDER 兼容）', () {
      const cfg = ChickenRiceConfig(
        scriptPath: 'C:\\t\\run.bat',
        overwrite: true,
      );
      final cmd = ChickenRiceService(cfg).buildCommand(['D:\\dir']);
      // --overwrite 在目录前，否则会被 base_dirs(REMAINDER) 吞掉
      expect(cmd[5], '--overwrite');
      expect(cmd[6], 'D:\\dir');
      expect(cmd.last, 'D:\\dir');
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
              stdoutLines: ['  VAD 处理中 3/120 (2.5%) on cuda'],
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

File createTempScript(String name) {
  final dir = Directory.systemTemp.createTempSync('cr_test');
  final f = File('${dir.path}/$name');
  f.writeAsStringSync('x');
  return f;
}

ProcessHandle _completedHandle() =>
    _FakeHandle(stdoutLines: const [], exitCode: 0);

class _FakeRunner implements ProcessRunner {
  final ProcessHandle Function(List<String> command,
      Map<String, String>? environment) onStart;

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