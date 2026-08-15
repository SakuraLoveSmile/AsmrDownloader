import 'dart:async';
import 'dart:io';

import 'package:asmr_downloader/services/transcribe/chicken_rice_config.dart';
import 'package:asmr_downloader/services/transcribe/chicken_rice_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChickenRiceConfig', () {
    test('默认配置为 translate + lrc', () {
      const cfg = ChickenRiceConfig();
      expect(cfg.task, 'translate');
      expect(cfg.subFormats, 'lrc');
      expect(cfg.device, 'auto');
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

    test('bat/exe 存在时返回 null', () {
      final bat = createTempScript('run.bat');
      expect(
          ChickenRiceService(ChickenRiceConfig(scriptPath: bat.path))
              .probeScript(),
          isNull);
      bat.deleteSync();

      final exe = createTempScript('infer.exe');
      expect(
          ChickenRiceService(ChickenRiceConfig(scriptPath: exe.path))
              .probeScript(),
          isNull);
      exe.deleteSync();
    });
  });

  group('buildCommand', () {
    test('exe 模式：拼接基础参数 + base_dirs', () {
      const cfg = ChickenRiceConfig(scriptPath: 'C:\\t\\infer.exe');
      final svc = ChickenRiceService(cfg);
      final cmd = svc.buildCommand('D:\\asmr\\RJ1');
      expect(cmd.first, 'C:\\t\\infer.exe');
      expect(cmd, contains('--device=auto'));
      expect(cmd, contains('--task=translate'));
      expect(cmd, contains('--sub_formats=lrc'));
      expect(cmd, contains('--audio_suffixes=wav,flac,mp3,m4a,aac,ogg'));
      expect(cmd.last, 'D:\\asmr\\RJ1');
    });

    test('exe 模式：task=transcribe + overwrite 时追加参数', () {
      const cfg = ChickenRiceConfig(
        scriptPath: '/opt/infer',
        task: 'transcribe',
        overwrite: true,
      );
      final cmd = ChickenRiceService(cfg).buildCommand('dir');
      expect(cmd, contains('--task=transcribe'));
      expect(cmd, contains('--overwrite'));
    });

    test('bat 模式：经 cmd /c call 调用，只传目录，不带任务/设备参数', () {
      const cfg = ChickenRiceConfig(scriptPath: 'C:\\t\\运行(翻译)(GPU).bat');
      final cmd = ChickenRiceService(cfg).buildCommand('D:\\asmr\\RJ1');
      expect(cmd.take(4), ['cmd.exe', '/d', '/c', 'call']);
      expect(cmd[4], 'C:\\t\\运行(翻译)(GPU).bat');
      expect(cmd[5], 'D:\\asmr\\RJ1');
      expect(cmd.length, 6);
      expect(cmd.any((a) => a.startsWith('--task')), isFalse);
      expect(cmd.any((a) => a.startsWith('--device')), isFalse);
      expect(cmd.any((a) => a.startsWith('--sub_formats')), isFalse);
    });

    test('bat 模式：overwrite 时追加 --overwrite', () {
      const cfg = ChickenRiceConfig(
        scriptPath: 'C:\\t\\run.bat',
        overwrite: true,
      );
      final cmd = ChickenRiceService(cfg).buildCommand('D:\\dir');
      expect(cmd.last, '--overwrite');
    });
  });

  group('run', () {
    test('脚本未配置时返回 false 且不调用进程', () async {
      var started = false;
      final svc = ChickenRiceService(
        const ChickenRiceConfig(),
        runner: _FakeRunner((_) {
          started = true;
          return _completedHandle();
        }),
      );
      final ok = await svc.run(dirs: ['/some/dir']);
      expect(ok, false);
      expect(started, false);
    });

    test('脚本不存在时返回 false', () async {
      var started = false;
      final svc = ChickenRiceService(
        const ChickenRiceConfig(scriptPath: '/nope/run.bat'),
        runner: _FakeRunner((_) {
          started = true;
          return _completedHandle();
        }),
      );
      final ok = await svc.run(dirs: ['/some/dir']);
      expect(ok, false);
      expect(started, false);
    });

    test('退出码 0 返回 true', () async {
      // 需要一个真实存在的临时 bat 作为脚本，probe 才通过
      final tmp = createTempScript('infer.bat');
      final svc = ChickenRiceService(
        ChickenRiceConfig(scriptPath: tmp.path),
        runner: _FakeRunner((_) => _completedHandle()),
      );
      expect(await svc.run(dirs: ['/some/dir']), true);
      expect(svc.probeScript(), isNull);
      tmp.deleteSync();
    });

    test('非 0 退出码返回 false 并把进度回调传递', () async {
      final tmp = createTempScript('infer.bat');
      final received = <int>[];
      final svc = ChickenRiceService(
        ChickenRiceConfig(scriptPath: tmp.path),
        runner: _FakeRunner((_) => _FakeHandle(
              stdoutLines: ['  VAD 处理中 3/120 (2.5%) on cuda'],
              exitCode: 1,
            )),
      );
      final ok = await svc.run(
        dirs: ['/d'],
        onProgress: (p) => received.add(p.done),
      );
      expect(ok, false);
      expect(received, [3]);
      tmp.deleteSync();
    });

    test('请求取消时 kill 进程并返回 false', () async {
      final tmp = createTempScript('infer.bat');
      var killed = false;
      // exitCode 在 kill 之后才完成，模拟真实进程被终止的时序
      final exitCompleter = Completer<int>();
      final svc = ChickenRiceService(
        ChickenRiceConfig(scriptPath: tmp.path),
        runner: _FakeRunner((_) => _FakeHandle(
              stdoutLines: const [],
              exitCodeFuture: exitCompleter.future,
              killCallback: () {
                killed = true;
                exitCompleter.complete(130); // SIGINT
              },
            )),
      );
      final ok = await svc.run(
        dirs: ['/d'],
        isCancelled: () => true,
      );
      expect(ok, false);
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
  final ProcessHandle Function(List<String> command) onStart;

  _FakeRunner(this.onStart);

  @override
  Future<ProcessHandle> start(List<String> command,
      {String? workingDirectory}) {
    return Future.value(onStart(command));
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
    int exitCode = 0,
    this.killCallback,
    Future<int>? exitCodeFuture,
  })  : _exitCode = exitCode,
        _exitCodeFuture = exitCodeFuture {
    for (final l in stdoutLines) {
      _out.add(l);
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
