import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:asmr_downloader/services/transcribe/chicken_rice_service.dart';
import 'package:asmr_downloader/utils/log.dart';

/// Runs child-process I/O in a long-lived isolate so Windows process creation
/// and antivirus scanning cannot block Flutter's UI isolate.
class IsolateProcessRunner implements ProcessRunner {
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _commandPort;
  Future<void>? _startup;
  int _nextId = 0;
  bool _disposed = false;
  final Map<int, _IsolateProcessHandle> _handles = {};

  @override
  Future<ProcessHandle> start(List<String> command,
      {String? workingDirectory, Map<String, String>? environment}) async {
    if (_disposed) {
      throw StateError('IsolateProcessRunner has been disposed');
    }

    final fallback = await _ensureStarted();
    if (fallback != null) {
      return fallback.start(command,
          workingDirectory: workingDirectory, environment: environment);
    }

    final id = ++_nextId;
    final handle = _IsolateProcessHandle(id, _sendKill);
    final started = Completer<void>();
    _handles[id] = handle;
    handle._started = started;

    try {
      _commandPort!.send(<Object?>[
        'start',
        id,
        command,
        workingDirectory,
        environment,
      ]);
      await started.future;
      return handle;
    } catch (_) {
      _handles.remove(id);
      handle._close();
      rethrow;
    }
  }

  /// Releases the worker isolate and any process handles owned by it.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final handle in _handles.values.toList()) {
      handle.kill();
      handle._completeExit(-1);
    }
    _handles.clear();
    _receivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commandPort = null;
  }

  Future<RealProcessRunner?> _ensureStarted() async {
    if (_commandPort != null) return null;
    _startup ??= _startWorker();
    try {
      await _startup;
      return null;
    } catch (e) {
      // The fallback is intentionally per-run: a worker startup failure should
      // not make transcription permanently unavailable for this app session.
      Log.warning('isolate process runner unavailable, falling back: $e');
      return const RealProcessRunner();
    }
  }

  Future<void> _startWorker() async {
    final receivePort = ReceivePort();
    _receivePort = receivePort;
    final ready = Completer<void>();
    late final StreamSubscription<Object?> subscription;
    subscription = receivePort.listen((message) {
      if (message is SendPort) {
        _commandPort = message;
        if (!ready.isCompleted) ready.complete();
        return;
      }
      if (message is! List || message.length < 2) return;
      _handleMessage(message);
    });

    try {
      _isolate = await Isolate.spawn<List<Object?>>(
        _processWorkerMain,
        <Object?>[receivePort.sendPort],
        errorsAreFatal: false,
      );
      await ready.future.timeout(const Duration(seconds: 5));
    } catch (e) {
      await subscription.cancel();
      receivePort.close();
      _receivePort = null;
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      rethrow;
    }
  }

  void _handleMessage(List<dynamic> message) {
    final type = message[0];
    final id = message[1] is int ? message[1] as int : -1;
    final handle = _handles[id];
    if (handle == null) return;

    switch (type) {
      case 'started':
        final elapsed = message.length > 2 ? message[2] : 0;
        Log.info('chickenRice process spawned in worker '
            '(pid=${message.length > 3 ? message[3] : '?'}, ${elapsed}ms)');
        handle._completeStarted();
        break;
      case 'stdout':
        if (message.length > 2) {
          handle._stdoutController.add(message[2] as String);
        }
        break;
      case 'stderr':
        if (message.length > 2) {
          handle._stderrController.add(message[2] as String);
        }
        break;
      case 'exit':
        final code = message.length > 2 ? (message[2] as int? ?? -1) : -1;
        handle._completeExit(code);
        _handles.remove(id);
        break;
      case 'startError':
        final error =
            message.length > 2 ? message[2].toString() : 'unknown error';
        handle._completeStartError(StateError(error));
        _handles.remove(id);
        break;
    }
  }

  void _sendKill(int id) {
    _commandPort?.send(<Object?>['kill', id]);
  }
}

class _IsolateProcessHandle implements ProcessHandle {
  _IsolateProcessHandle(this._id, this._killCallback);

  final int _id;
  final void Function(int id) _killCallback;
  final StreamController<String> _stdoutController = StreamController<String>();
  final StreamController<String> _stderrController = StreamController<String>();
  final Completer<int> _exit = Completer<int>();
  Completer<void>? _started;
  bool _closed = false;

  @override
  Stream<String> get stdout => _stdoutController.stream;

  @override
  Stream<String> get stderr => _stderrController.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void kill() => _killCallback(_id);

  void _completeStarted() {
    if (!(_started?.isCompleted ?? true)) _started!.complete();
  }

  void _completeStartError(Object error) {
    if (!(_started?.isCompleted ?? true)) _started!.completeError(error);
    _completeExit(-1);
  }

  void _completeExit(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
    _close();
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    if (!(_started?.isCompleted ?? true)) {
      _started!.completeError(StateError('process worker closed'));
    }
    _stdoutController.close();
    _stderrController.close();
  }
}

/// Isolate entry point. Messages use only primitive/list values so the
/// protocol remains compatible with all Dart VM isolate boundaries.
void _processWorkerMain(List<Object?> args) {
  final host = args.single as SendPort;
  final commands = ReceivePort();
  host.send(commands.sendPort);
  final processes = <int, Process>{};

  commands.listen((message) async {
    if (message is! List || message.isEmpty) return;
    final type = message[0];
    final id = message.length > 1 ? message[1] as int : -1;

    if (type == 'kill') {
      final process = processes[id];
      if (process == null) return;
      try {
        var exitCode = -1;
        if (Platform.isWindows) {
          // taskkill /t /f terminates the whole tree.
          await Process.run('taskkill', ['/pid', '${process.pid}', '/t', '/f']);
          await process.exitCode.catchError((_) => -1);
          try {
            exitCode =
                await process.exitCode.timeout(const Duration(seconds: 3));
          } catch (_) {
            exitCode = -1;
          }
        } else {
          // POSIX shells defer SIGTERM while waiting on a child, so a plain
          // kill may not terminate `sh -c 'sleep N'` until the child exits.
          // Escalate to SIGKILL after a grace period.
          process.kill();
          try {
            exitCode =
                await process.exitCode.timeout(const Duration(seconds: 2));
          } on TimeoutException {
            process.kill(ProcessSignal.sigkill);
            try {
              exitCode =
                  await process.exitCode.timeout(const Duration(seconds: 2));
            } catch (_) {
              exitCode = -1;
            }
          }
        }
        // The killed process may leave children holding the output pipes open
        // (e.g. `sh -c 'sleep 30'`), so the normal exit listener below would
        // only report completion when those children finish. Report the exit
        // here so handles complete promptly; a later duplicate 'exit' message
        // is ignored by [IsolateProcessRunner._handleMessage].
        processes.remove(id);
        host.send(<Object?>['exit', id, exitCode]);
      } catch (_) {}
      return;
    }
    if (type != 'start' || message.length < 5) return;

    final command = (message[2] as List).cast<String>();
    final workingDirectory = message[3] as String?;
    final environment = (message[4] as Map?)?.cast<String, String>();
    final stopwatch = Stopwatch()..start();
    try {
      final process = await Process.start(
        command.first,
        command.skip(1).toList(),
        workingDirectory: workingDirectory,
        environment: environment == null
            ? null
            : {...Platform.environment, ...environment},
      );
      processes[id] = process;
      try {
        process.stdin.close();
      } catch (_) {}
      host.send(
          <Object?>['started', id, stopwatch.elapsedMilliseconds, process.pid]);

      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();
      process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(
        (line) => host.send(<Object?>['stdout', id, line]),
        onError: (_) {},
        onDone: () {
          if (!stdoutDone.isCompleted) stdoutDone.complete();
        },
      );
      process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(
        (line) => host.send(<Object?>['stderr', id, line]),
        onError: (_) {},
        onDone: () {
          if (!stderrDone.isCompleted) stderrDone.complete();
        },
      );

      final exitCode = await process.exitCode;
      await Future.wait([stdoutDone.future, stderrDone.future]);
      processes.remove(id);
      host.send(<Object?>['exit', id, exitCode]);
    } catch (e) {
      processes.remove(id);
      host.send(<Object?>['startError', id, '$e']);
    }
  });
}
