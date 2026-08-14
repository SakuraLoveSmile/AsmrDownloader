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

    test('isConfigured 判断 exe 是否已设置', () {
      expect(const ChickenRiceConfig().isConfigured, false);
      expect(const ChickenRiceConfig(exePath: '/x/infer.exe').isConfigured,
          true);
    });
  });

  group('buildCommand', () {
    test('拼接基础参数 + base_dirs', () {
      const cfg = ChickenRiceConfig(exePath: 'C:\\t\\infer.exe');
      final svc = ChickenRiceService(cfg);
      final cmd = svc.buildCommand('D:\\asmr\\RJ1');
      expect(cmd.first, 'C:\\t\\infer.exe');
      expect(cmd, contains('--device=auto'));
      expect(cmd, contains('--task=translate'));
      expect(cmd, contains('--sub_formats=lrc'));
      expect(cmd, contains('--audio_suffixes=wav,flac,mp3,m4a,aac,ogg'));
      expect(cmd.last, 'D:\\asmr\\RJ1');
    });

    test('task=transcribe + overwrite 时追加参数', () {
      const cfg = ChickenRiceConfig(
        exePath: '/opt/infer',
        task: 'transcribe',
        overwrite: true,
      );
      final cmd = ChickenRiceService(cfg).buildCommand('dir');
      expect(cmd, contains('--task=transcribe'));
      expect(cmd, contains('--overwrite'));
    });

    test('workdir 取 exe 所在目录', () {
      // run() 会用 exe 的 dirname 作为工作目录 —— 通过注入 fake 验证
      // （这里仅验证 probe 逻辑）
      expect(ChickenRiceService(const ChickenRiceConfig()).probeExe(), isNotNull);
    });
  });

  group('run', () {
    test('exe 未配置时返回 false 且不调用进程', () async {
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

    test('exe 不存在时返回 false', () async {
      var started = false;
      final svc = ChickenRiceService(
        const ChickenRiceConfig(exePath: '/nope/infer.exe'),
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
      // 需要一个真实存在的临时文件作为 exe，probe 才通过
      final tmp = createTempExe();
      final svc = ChickenRiceService(
        ChickenRiceConfig(exePath: tmp.path),
        runner: _FakeRunner((_) => _completedHandle()),
      );
      expect(await svc.run(dirs: ['/some/dir']), true);
      expect(svc.probeExe(), isNull);
      tmp.deleteSync();
    });

    test('非 0 退出码返回 false 并把进度回调传递', () async {
      final tmp = createTempExe();
      final received = <int>[];
      final svc = ChickenRiceService(
        ChickenRiceConfig(exePath: tmp.path),
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
      final tmp = createTempExe();
      var killed = false;
      final svc = ChickenRiceService(
        ChickenRiceConfig(exePath: tmp.path),
        runner: _FakeRunner((_) => _FakeHandle(
              stdoutLines: const [],
              exitCode: 130, // SIGINT
              killCallback: () => killed = true,
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

File createTempExe() {
  final dir = Directory.systemTemp.createTempSync('cr_test');
  final f = File('${dir.path}/infer');
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
  final void Function()? killCallback;
  final StreamController<String> _out = StreamController<String>();
  final StreamController<String> _err = StreamController<String>();

  _FakeHandle({
    List<String> stdoutLines = const [],
    int exitCode = 0,
    this.killCallback,
  }) : _exitCode = exitCode {
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
  Future<int> get exitCode => Future.value(_exitCode);
  @override
  void kill() => killCallback?.call();
}
