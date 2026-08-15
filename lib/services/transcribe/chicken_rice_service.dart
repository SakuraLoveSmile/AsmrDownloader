import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:asmr_downloader/services/transcribe/chicken_rice_config.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:path/path.dart' as p;

/// 转录进度（UI 推送用）。
class TranscribeProgress {
  final int done;
  final int total;
  final String currentFile;

  const TranscribeProgress({
    required this.done,
    required this.total,
    required this.currentFile,
  });

  double get percentage =>
      total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0).toDouble();
}

/// 一个正在运行的外部进程句柄，支持主动终止。
abstract class ProcessHandle {
  Stream<String> get stdout;
  Stream<String> get stderr;
  Future<int> get exitCode;

  /// 终止进程（尽力而为）。
  void kill();
}

/// 可注入的进程启动器（便于单测注入 fake）。
abstract class ProcessRunner {
  /// 启动 [command]，返回进程句柄。
  Future<ProcessHandle> start(List<String> command,
      {String? workingDirectory});
}

/// 真实以 dart:io [Process] 实现的进程启动器。
class RealProcessRunner implements ProcessRunner {
  const RealProcessRunner();

  @override
  Future<ProcessHandle> start(List<String> command,
      {String? workingDirectory}) async {
    final process = await Process.start(command.first, command.skip(1).toList(),
        workingDirectory: workingDirectory);
    final out = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final err = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    return _RealProcessHandle(process, out, err);
  }
}

class _RealProcessHandle implements ProcessHandle {
  final Process _process;
  final Stream<String> _stdout;
  final Stream<String> _stderr;

  _RealProcessHandle(this._process, this._stdout, this._stderr);

  @override
  Stream<String> get stdout => _stdout;
  @override
  Stream<String> get stderr => _stderr;
  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void kill() {
    try {
      if (Platform.isWindows) {
        // bat 经 cmd.exe 启动，只杀 cmd 会留下孤儿 infer.exe：
        // 用 taskkill 按 PID 树杀（/t 杀子进程树 /f 强制）。
        Process.run('taskkill', ['/pid', '${_process.pid}', '/t', '/f']);
      }
      _process.kill();
    } catch (_) {}
  }
}

/// 调用 ChickenRice（Faster-Whisper-TransWithAI-ChickenRice）生成本地字幕。
///
/// 两种调用模式：
/// - **bat 模式**（scriptPath 为 .bat/.cmd）：经 `cmd.exe /d /c call` 调用，
///   把作品目录作为参数传进去（等价于把文件夹拖到 bat 上）。翻译/转录与
///   设备由所选 bat 决定（bat 自带 `--device=...` 等参数），本服务不再拼接
///   任务/设备参数，只追加可选的 `--overwrite`。
/// - **exe 模式**（scriptPath 为 infer.exe）：直接调用并拼接全部参数。
///
/// 关键设计：
/// - **工作目录 = 脚本所在目录**（ChickenRice 运行时 `os.chdir` 到 exe 目录
///   查找 `models/whisper_vad.onnx` 与主模型，不设置会找不到模型）。
/// - **把目录交给 ChickenRice 递归扫描**：传入的目录作为 base_dirs，
///   ChickenRice 对已存在字幕自动跳过（`--overwrite` 控制），天然增量。
/// - **进度解析 stdout**：ChickenRice 用 `\r` 刷新 VAD 进度并打进度日志，
///   无结构化输出，这里按日志里的 `n/total` 文本估算。
class ChickenRiceService {
  final ChickenRiceConfig config;
  final ProcessRunner _runner;

  ChickenRiceService(this.config, {ProcessRunner? runner})
      : _runner = runner ?? const RealProcessRunner();

  /// 探测脚本是否可用（存在且扩展名受支持）。返回 null 表示 OK，否则错误说明。
  String? probeScript() {
    final path = config.scriptPath;
    if (path.isEmpty) return '未配置 ChickenRice 启动脚本';
    if (!File(path).existsSync()) return '文件不存在: $path';
    if (!config.isBat && !config.isExe) {
      return '不支持的文件类型（仅支持 .bat / .cmd / .exe）: $path';
    }
    return null;
  }

  /// 拼接传给 ChickenRice 的命令（含 base_dirs 的 [dirs]）。
  List<String> buildCommand(String dirs) {
    if (config.isBat) {
      // bat 模式：任务/设备由 bat 决定，只传目录 + 可选 --overwrite。
      // `call` 前缀避免 cmd /c 对首引号参数的剥离规则破坏带空格路径。
      final args = <String>[
        'cmd.exe',
        '/d',
        '/c',
        'call',
        config.scriptPath,
        dirs,
      ];
      if (config.overwrite) args.add('--overwrite');
      return args;
    }
    final args = <String>[
      '--device=${config.device}',
      '--task=${config.task}',
      '--sub_formats=${config.subFormats}',
      '--audio_suffixes=${config.audioSuffixes}',
    ];
    if (config.overwrite) args.add('--overwrite');
    if (config.modelNameOrPath.isNotEmpty) {
      args.add('--model_name_or_path=${config.modelNameOrPath}');
    }
    args.add(dirs);
    return [config.scriptPath, ...args];
  }

  /// 在一个/多个目录（或文件）上运行 ChickenRice。
  ///
  /// [dirs] 传给 base_dirs 的列表（空格分隔拼接）。
  /// [onProgress] 每解析到一次进度回调；[isCancelled] 返回 true 时 kill 进程。
  /// 返回 true 表示正常退出（退出码 0 且未被取消）。
  Future<bool> run({
    required List<String> dirs,
    void Function(TranscribeProgress)? onProgress,
    bool Function() isCancelled = _never,
  }) async {
    if (dirs.isEmpty) return true;
    final probe = probeScript();
    if (probe != null) {
      Log.error('chickenRice run failed: $probe');
      return false;
    }

    final command = buildCommand(dirs.join(' '));
    final workDir = p.dirname(config.scriptPath);
    Log.info('chickenRice run: ${command.join(' ')}\n'
        'workingDir: $workDir');

    ProcessHandle? handle;
    try {
      handle = await _runner.start(command, workingDirectory: workDir);
    } catch (e) {
      Log.error('chickenRice failed to start: $e');
      return false;
    }
    return _await(handle, onProgress: onProgress, isCancelled: isCancelled);
  }

  /// 便捷：对单个作品目录运行翻译。
  Future<bool> runOnDir(String dir,
      {void Function(TranscribeProgress)? onProgress,
      bool Function() isCancelled = _never}) {
    return run(dirs: [dir], onProgress: onProgress, isCancelled: isCancelled);
  }

  Future<bool> _await(ProcessHandle handle,
      {void Function(TranscribeProgress)? onProgress,
      required bool Function() isCancelled}) async {
    final stderrLines = <String>[];
    final cancelled = Completer<bool>();

    final subOut = handle.stdout.listen((line) {
      _parseProgress(line, onProgress);
    });
    final subErr = handle.stderr.listen((line) {
      if (line.trim().isNotEmpty) {
        if (stderrLines.length >= 40) stderrLines.removeAt(0);
        stderrLines.add(line);
      }
    });

    // 取消轮询：isCancelled 翻转时 kill 进程
    final cancelTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (isCancelled() && !cancelled.isCompleted) {
        cancelled.complete(true);
        handle.kill();
      }
    });

    int exitCode;
    try {
      exitCode = await handle.exitCode;
    } catch (e) {
      Log.error('chickenRice await exitCode failed: $e');
      exitCode = -1;
    }
    cancelTimer.cancel();

    final wasCancelled = cancelled.isCompleted;
    final errTail = stderrLines.reversed.take(8).toList().reversed.join('\n');
    if (exitCode == 0 && !wasCancelled) {
      Log.info('chickenRice completed, exit code 0');
      subOut.cancel();
      subErr.cancel();
      return true;
    }
    Log.error('chickenRice exited with code $exitCode'
        '${wasCancelled ? ' (cancelled)' : ''}\nstderr tail:\n$errTail');
    subOut.cancel();
    subErr.cancel();
    return false;
  }

  static bool _never() => false;

  /// 从 ChickenRice stdout 行解析进度（形如 `  3/120 (...)`）。
  void _parseProgress(String line, void Function(TranscribeProgress)? onProgress) {
    if (onProgress == null) return;
    final m = RegExp(r'(\d+)\s*/\s*(\d+)').firstMatch(line);
    if (m == null) return;
    final done = int.tryParse(m.group(1)!);
    final total = int.tryParse(m.group(2)!);
    if (done == null || total == null || total <= 0) return;
    onProgress(TranscribeProgress(done: done, total: total, currentFile: ''));
  }
}
