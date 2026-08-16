import 'dart:io';

import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import 'package:path/path.dart' as p;

/// 单条应用日志（供应用内实时日志查看器展示）
class LogEntry {
  LogEntry({required this.time, required this.level, required this.text});

  final DateTime time;

  /// TRACE / DEBUG / INFO / WARN / ERROR / FATAL
  final String level;

  /// 日志正文（含 error/stackTrace 附加信息，可多行）
  final String text;

  String format() {
    final t = time;
    String two(int v) => v.toString().padLeft(2, '0');
    final ts = '${two(t.month)}-${two(t.day)} ${two(t.hour)}:'
        '${two(t.minute)}:${two(t.second)}';
    return '[$ts] $level $text';
  }
}

/// 内存日志环形缓冲：无论是否写文件都记录，供应用内「在线日志」
/// 实时展示。条目变化时通知监听者（查看器打开时才订阅）。
class LogBuffer extends ChangeNotifier {
  static const int maxEntries = 1000;

  final List<LogEntry> _entries = [];

  List<LogEntry> get entries => List.unmodifiable(_entries);

  void add(LogEntry entry) {
    _entries.add(entry);
    while (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
    notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }
}

/// 自定义日志输出：
/// - debug 构建默认只输出到控制台；开启 Debug 模式后同时写入文件。
/// - release 构建默认写入文件（保持历史行为）；关闭 Debug 模式后不再写文件。
/// - 所有日志同时进入内存缓冲 [Log.buffer]，可在应用内实时查看。
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

  /// 内存日志缓冲（应用内实时日志查看器的数据源）
  static final LogBuffer buffer = LogBuffer();

  static void _record(String level, String text) {
    buffer.add(LogEntry(time: DateTime.now(), level: level, text: text));
  }

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
    _record('TRACE', message);
    _instance._logger.t(message);
  }

  static void debug(String message) {
    _record('DEBUG', message);
    _instance._logger.d(message);
  }

  static void info(String message) {
    _record('INFO', message);
    _instance._logger.i(message);
  }

  static void warning(String message) {
    _record('WARN', message);
    _instance._logger.w(message);
  }

  static void error(
    String message, {
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final text = StringBuffer(message);
    if (error != null) text.write('\nerror: $error');
    if (stackTrace != null) text.write('\n$stackTrace');
    _record('ERROR', text.toString());
    _instance._logger.e(
      message,
      time: time,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void fatal(String message) {
    _record('FATAL', message);
    _instance._logger.f(message);
  }
}
