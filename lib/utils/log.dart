import 'dart:io';

import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import 'package:path/path.dart' as p;

/// 自定义日志输出：
/// - debug 构建默认只输出到控制台；开启 Debug 模式后同时写入文件。
/// - release 构建默认写入文件（保持历史行为）；关闭 Debug 模式后不再写文件。
class _AppLogOutput extends LogOutput {
  IOSink? _sink;
  bool _fileEnabled = !kDebugMode;

  void setFileEnabled(bool enabled) {
    _fileEnabled = enabled;
  }

  @override
  void output(OutputEvent event) {
    if (kDebugMode) {
      for (final line in event.lines) {
        print(line);
      }
    }

    if (_fileEnabled) {
      _sink ??= Log._getLogFile().openWrite(mode: FileMode.writeOnlyAppend);
      _sink?.writeAll(event.lines, '\n');
      _sink?.writeln();
    }
  }

  @override
  Future<void> destroy() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }
}

class Log {
  // named constructor
  Log._internal() {
    _appOutput = _AppLogOutput();
    _logger = kDebugMode
        ? Logger(
            printer: PrettyPrinter(
              methodCount: 0,
              dateTimeFormat: DateTimeFormat.dateAndTime,
            ),
            output: _appOutput,
          )
        : Logger(
            filter: ProductionFilter(),
            printer: PrettyPrinter(
                methodCount: 0,
                colors: false,
                dateTimeFormat: DateTimeFormat.dateAndTime),
            output: _appOutput,
            level: Level.info,
          );
  }

  static File _getLogFile() {
    final logFilePath = p.join(getAppDataDir(), 'debug', 'asmr_downloader.log');
    final logFile = File(logFilePath);

    if (!logFile.existsSync()) {
      logFile.createSync(recursive: true);
    }

    if (logFile.lengthSync() > 1024 * 1024 * 5) {
      try {
        logFile.renameSync('$logFilePath.old');
      } catch (_) {}
    }

    return logFile;
  }

  late final _AppLogOutput _appOutput;
  late final Logger _logger;

  static final Log _instance = Log._internal();
  static Logger get logger => _instance._logger;

  /// 是否已开启文件日志输出。
  static bool get fileOutputEnabled =>
      _instance._appOutput._fileEnabled;

  /// 运行时开关：开启/关闭把日志写入文件。
  /// 默认 debug 构建关闭、release 构建开启。
  static void setFileOutputEnabled(bool enabled) {
    if (fileOutputEnabled == enabled) return;
    _instance._appOutput.setFileEnabled(enabled);
    final state = enabled ? 'enabled' : 'disabled';
    Log.info('file log output $state');
  }

  static void trace(String message) {
    _instance._logger.t(message);
  }

  static void debug(String message) {
    _instance._logger.d(message);
  }

  static void info(String message) {
    _instance._logger.i(message);
  }

  static void warning(String message) {
    _instance._logger.w(message);
  }

  static void error(
    String message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _instance._logger.e(
      message,
      time: time,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void fatal(String message) {
    _instance._logger.f(message);
  }
}
