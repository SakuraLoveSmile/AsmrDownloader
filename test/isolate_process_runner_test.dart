import 'dart:io';

import 'package:asmr_downloader/services/transcribe/isolate_process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late IsolateProcessRunner runner;

  setUp(() {
    runner = IsolateProcessRunner();
  });

  tearDown(() async {
    await runner.dispose();
  });

  test('forwards stdout, stderr, and exit code', () async {
    final command = Platform.isWindows
        ? ['cmd.exe', '/c', 'echo out & echo err 1>&2']
        : ['sh', '-c', 'printf out; printf err 1>&2'];
    final handle = await runner.start(command);
    final stdout = <String>[];
    final stderr = <String>[];
    final outDone = handle.stdout.forEach(stdout.add);
    final errDone = handle.stderr.forEach(stderr.add);

    expect(await handle.exitCode, 0);
    await Future.wait([outDone, errDone]);
    expect(stdout.join(), contains('out'));
    expect(stderr.join(), contains('err'));
  });

  test('kill terminates the child process', () async {
    final command = Platform.isWindows
        ? ['cmd.exe', '/c', 'timeout /t 30 /nobreak >nul']
        : ['sh', '-c', 'sleep 30'];
    final handle = await runner.start(command);
    handle.kill();

    // kill 必须真正终止子进程；正常运行需 30s，远超等待上限
    final code = await handle.exitCode.timeout(const Duration(seconds: 10));
    expect(code, isNot(0));
  });

  test('start errors are returned to the caller', () async {
    final command = Platform.isWindows
        ? ['Z:\\does-not-exist\\invalid.exe']
        : ['/does-not-exist/invalid-command'];
    await expectLater(runner.start(command), throwsA(isA<Object>()));
  });
}
