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
  ///
  /// [environment] 为附加环境变量（与父进程环境合并后传入子进程）。
  Future<ProcessHandle> start(
    List<String> command, {
    String? workingDirectory,
    Map<String, String>? environment,
  });
}

/// 真实以 dart:io [Process] 实现的进程启动器。
class RealProcessRunner implements ProcessRunner {
  const RealProcessRunner();

  @override
  Future<ProcessHandle> start(List<String> command,
      {String? workingDirectory, Map<String, String>? environment}) async {
    final sw = Stopwatch()..start();
    final process = await Process.start(
      command.first,
      command.skip(1).toList(),
      workingDirectory: workingDirectory,
      environment:
          environment == null ? null : {...Platform.environment, ...environment},
    );
    // 诊断：Process.start 本身若耗时异常（杀软扫描/SmartScreen 等）
    // 会在这里暴露；正常应为毫秒级。
    Log.info('chickenRice process spawned: pid=${process.pid} '
        '(${sw.elapsedMilliseconds}ms)');
    // 关键修复：Dart 默认不关闭子进程 stdin（管道写端一直开着）。
    // ChickenRice 的 .bat 末尾都有 pause（从 stdin 等待按键），
    // 不关闭 stdin 会永久阻塞，导致 bat 模式运行永远不结束。
    // 显式 close 后子进程读到 EOF，pause 立即返回。
    try {
      process.stdin.close();
    } catch (_) {}
    // 容错解码：ChickenRice（Python 3.10）在中文 Windows 下管道输出为
    // GBK/cp936，严格 UTF-8 解码会抛 FormatException 中断进度解析；
    // allowMalformed 保证坏字节不致命（配合 PYTHONUTF8=1 环境变量双保险）。
    final out = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());
    final err = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
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
/// - **bat 模式**（scriptPath 为 .bat/.cmd）：优先解析 bat 内 infer.exe
///   调用行**直调 exe**（Dart 经 CreateProcessW 传参，UTF-16 无损，完全
///   绕开 cmd 的代码页转码/批处理解析问题）；解析失败（自定义 bat）时
///   回退 UTF-8 wrapper 真调用原 bat（等价于把文件夹拖到 bat 上），再
///   失败才用 cmd.exe /d /c call 兜底。翻译/转录与设备由所选 bat 决定
///   （bat 自带 --device=... 等参数），本服务只追加可选的 --overwrite
///   （注意必须放在目录参数**之前**，见 buildCommand）。
/// - **exe 模式**（scriptPath 为 infer.exe）：直接调用并拼接全部参数。
///
/// 关键设计：
/// - **工作目录 = 脚本所在目录**（ChickenRice 运行时 os.chdir 到 exe 目录
///   查找 models/whisper_vad.onnx 与主模型，不设置会找不到模型）。
/// - **把目录交给 ChickenRice 递归扫描**：传入的目录作为 base_dirs，
///   ChickenRice 对已存在字幕自动跳过（--overwrite 控制），天然增量。
/// - **stdin 立即关闭**：bat 末尾 pause 依赖 EOF 才能立即结束（见上）。
/// - **进度解析 stdout + stderr**：VAD 块进度（stdout，x/y）与每文件
///   进度（stderr，logger 的 正在处理（task，n/total）：path）都会被解析，
///   文件级进度优先，并提取当前文件名。
/// - **0 输出检测**：解析 stderr 的 找到 N 个文件待处理 /
///   未找到要处理的文件，避免「退出码 0 但什么都没生成」的假成功。
class ChickenRiceService {
  final ChickenRiceConfig config;
  final ProcessRunner _runner;
  final bool _skipPlatformCheck;
  final Directory? _tempDir;

  /// [skipPlatformCheck] 仅供单元测试在非 Windows 开发机上验证
  /// 进程/解析逻辑；生产代码不要传 true。
  /// [tempDir] 仅供测试注入（bat wrapper 生成目录），默认系统临时目录。
  ChickenRiceService(this.config,
      {ProcessRunner? runner,
      bool skipPlatformCheck = false,
      Directory? tempDir})
      : _runner = runner ?? const RealProcessRunner(),
        _skipPlatformCheck = skipPlatformCheck,
        _tempDir = tempDir;

  /// 子进程附加环境变量：强制 Python 使用 UTF-8 输出（PEP 540），
  /// 避免中文 Windows 下管道输出为 GBK 导致解码异常/打印崩溃。
  static const Map<String, String> kChildEnvironment = {'PYTHONUTF8': '1'};

  /// 探测脚本是否可用（存在且扩展名受支持）。返回 null 表示 OK，否则错误说明。
  String? probeScript() {
    final path = config.scriptPath;
    if (path.isEmpty) return '未配置 ChickenRice 启动脚本';
    if (!File(path).existsSync()) return '文件不存在: $path';
    if (!config.isBat && !config.isExe) {
      return '不支持的文件类型（仅支持 .bat / .cmd / .exe）: $path';
    }
    if (!Platform.isWindows && !_skipPlatformCheck) {
      return 'AI 字幕翻译仅支持 Windows（当前平台: ${Platform.operatingSystem}）';
    }
    return null;
  }

  /// 拼接传给 ChickenRice 的命令（base_dirs 为 [dirs]，每个目录独立参数）。
  List<String> buildCommand(List<String> dirs) {
    if (config.isBat) {
      // bat 模式按可靠性排序的三级回退：
      //
      // 1) **解析 bat 直调 exe**（首选，官方 release bat 全部可解析）：
      //    Dart Process.start 经 CreateProcessW 传参（UTF-16），中文 bat
      //    文件名、日文假名目录等一律无损，且完全不经过 cmd.exe，绕开
      //    其 GBK 命令行转码与批处理解析器对 UTF-8 内容的处理缺陷。
      // 2) **UTF-8 wrapper 真调用原 bat**（自定义 bat 无法解析时）：
      //    保留原 bat 全部行为（参数预设、echo 提示、拖放逻辑），路径写进
      //    临时 wrapper 文件而非 cmd 命令行参数：
      //      @echo off
      //      chcp 65001 >nul
      //      call "<原bat>" "<目录1>" "<目录2>" ...
      //    cmd 启动时按 OEM 代码页（中文系统=GBK）转码命令行参数，日文
      //    假名等非 GBK 字符会变成 '?'；而 wrapper 路径为纯 ASCII 不受
      //    影响。注意：wrapper 方案在部分 Windows 版本上仍可能因 cmd 批
      //    处理解析器的 UTF-8 处理缺陷失败（call 行被损坏，报「不是内部
      //    或外部命令」退出码 1），故只作为非官方 bat 的兜底。
      // 3) **cmd call 兜底**（wrapper 生成也失败时，与旧行为一致）。
      final parsed = _parseBatInvocation();
      if (parsed != null && File(parsed.exePath).existsSync()) {
        final args = <String>[parsed.exePath, ...parsed.args];
        // --overwrite 必须放在目录**之前** —— ChickenRice 的 base_dirs
        // 是 argparse.REMAINDER，位置参数之后的任何 token（含 --overwrite）
        // 都会被吞进 base_dirs 而静默失效。
        if (config.overwrite) args.add('--overwrite');
        args.addAll(dirs);
        return args;
      }
      final wrapper = _buildBatWrapperCommand(dirs);
      if (wrapper != null) return wrapper;
      // 解析与 wrapper 均失败：最后回退 cmd call（与旧行为一致）。
      final args = <String>[
        'cmd.exe',
        '/d',
        '/c',
        'call',
        config.scriptPath,
      ];
      if (config.overwrite) args.add('--overwrite');
      args.addAll(dirs);
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
    args.addAll(dirs);
    return [config.scriptPath, ...args];
  }

  /// 在一个/多个目录（或文件）上运行 ChickenRice。
  ///
  /// [dirs] 传给 base_dirs 的列表（每个目录独立 argv 元素，支持空格路径）。
  /// [onProgress] 每解析到一次进度回调；[isCancelled] 返回 true 时 kill 进程。
  Future<TranscribeResult> run({
    required List<String> dirs,
    void Function(TranscribeProgress)? onProgress,
    bool Function() isCancelled = _never,
  }) async {
    if (dirs.isEmpty) {
      return const TranscribeResult(success: true, exitCode: 0);
    }
    final probe = probeScript();
    if (probe != null) {
      Log.error('chickenRice run failed: $probe');
      return TranscribeResult(success: false, exitCode: -1, error: probe);
    }

    final command = buildCommand(dirs);
    final workDir = p.dirname(config.scriptPath);
    Log.info('chickenRice run: ${command.join(' ')}\n'
        'workingDir: $workDir');

    // bat wrapper 的临时文件：运行结束后清理
    final wrapperPath = _isBatWrapperCommand(command) ? command.last : null;

    ProcessHandle? handle;
    try {
      handle = await _runner.start(command,
          workingDirectory: workDir, environment: kChildEnvironment);
    } catch (e) {
      Log.error('chickenRice failed to start: $e');
      _cleanupWrapper(wrapperPath);
      return TranscribeResult(success: false, exitCode: -1, error: '$e');
    }
    final result =
        await _await(handle, onProgress: onProgress, isCancelled: isCancelled);
    _cleanupWrapper(wrapperPath);
    return result;
  }

  /// 生成调用所选 bat 的临时 UTF-8 wrapper 命令；失败返回 null。
  ///
  /// wrapper 内容（chcp 65001 后 cmd 按 UTF-8 读取后续行，路径无损）：
  /// ```bat
  /// @echo off
  /// chcp 65001 >nul
  /// call "原bat路径" --overwrite "目录1" "目录2"
  /// ```
  /// 退出码 = 原 bat 内 infer.exe 的退出码（call 透传 ERRORLEVEL）。
  List<String>? _buildBatWrapperCommand(List<String> dirs) {
    try {
      final tmpDir = _tempDir ?? Directory.systemTemp;
      final wrapper = File(p.join(
          tmpDir.path,
          'asmr_cr_${DateTime.now().microsecondsSinceEpoch}.bat'));
      final buf = StringBuffer()
        ..writeln('@echo off')
        ..writeln('chcp 65001 >nul')
        ..write('call "${_escapeBatPath(config.scriptPath)}"');
      if (config.overwrite) buf.write(' --overwrite');
      for (final d in dirs) {
        buf.write(' "${_escapeBatPath(d)}"');
      }
      buf.writeln();
      // 文件以 UTF-8 BOM 开头：Win11 24H2+ 的 cmd 见 BOM 会原生按 UTF-8
      // 解析整个文件；旧版 cmd 不识别 BOM 时会把 BOM 三字节卷进首行，
      // 首行保持 `@echo off`——即使被 BOM 字节污染，也只是该行被回显
      // 一次（stderr 无害文本），命令本身仍会执行。
      wrapper.writeAsStringSync('\uFEFF${buf.toString()}', encoding: utf8);
      return ['cmd.exe', '/d', '/c', wrapper.path];
    } catch (e) {
      Log.warning('chickenRice create bat wrapper failed: $e');
      return null;
    }
  }

  /// bat 路径写进 wrapper 时的转义：`%` 是 cmd 变量展开符，需写成 `%%`。
  /// （`"` 在 Windows 文件名中非法；`&|<>^` 在引号内安全。）
  static String _escapeBatPath(String path) => path.replaceAll('%', '%%');

  /// 判断 [command] 是否为 bat wrapper 调用（cmd.exe /d /c + wrapper.bat）。
  static bool _isBatWrapperCommand(List<String> command) {
    if (command.length != 4) return false;
    if (command[0].toLowerCase() != 'cmd.exe') return false;
    final w = command[3].toLowerCase();
    return w.endsWith('.bat') || w.endsWith('.cmd');
  }

  static void _cleanupWrapper(String? wrapperPath) {
    if (wrapperPath == null) return;
    try {
      File(wrapperPath).deleteSync();
    } catch (_) {}
  }

  /// 便捷：对单个作品目录运行翻译。
  Future<TranscribeResult> runOnDir(String dir,
      {void Function(TranscribeProgress)? onProgress,
      bool Function() isCancelled = _never}) {
    return run(dirs: [dir], onProgress: onProgress, isCancelled: isCancelled);
  }

  Future<TranscribeResult> _await(ProcessHandle handle,
      {void Function(TranscribeProgress)? onProgress,
      required bool Function() isCancelled}) async {
    final stderrLines = <String>[];
    // 处理文件数：null = 未解析；0 = 明确「未找到要处理的文件」。
    int? filesProcessed;
    final cancelled = Completer<bool>();

    final subOut = handle.stdout.listen(
      (line) {
        _parseProgress(line, onProgress);
      },
      onError: (Object e) =>
          Log.warning('chickenRice stdout stream error: $e'),
    );
    final subErr = handle.stderr.listen(
      (line) {
        // 每文件进度（logger 输出走 stderr）同样参与进度解析
        _parseProgress(line, onProgress);
        filesProcessed = _parseFilesProcessed(line, filesProcessed);
        if (line.trim().isNotEmpty) {
          if (stderrLines.length >= 40) stderrLines.removeAt(0);
          stderrLines.add(line);
        }
      },
      onError: (Object e) =>
          Log.warning('chickenRice stderr stream error: $e'),
    );

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
    subOut.cancel();
    subErr.cancel();
    if (exitCode == 0 && !wasCancelled) {
      Log.info('chickenRice completed, exit code 0, filesProcessed=$filesProcessed');
      return TranscribeResult(
        success: true,
        exitCode: 0,
        filesProcessed: filesProcessed,
      );
    }
    Log.error('chickenRice exited with code $exitCode'
        '${wasCancelled ? ' (cancelled)' : ''}\nstderr tail:\n$errTail');
    return TranscribeResult(
      success: false,
      exitCode: exitCode,
      error: errTail,
      filesProcessed: filesProcessed,
    );
  }

  static bool _never() => false;

  /// 每文件进度行（stderr logger 输出），如：
  /// zh: 正在处理（translate，3/8）：D:\asmr\RJ1\e01.wav
  /// en: Processing (translate) (3/8): D:\asmr\RJ1\e01.wav
  /// zh 旧文案: 正在翻译（3/8）：D:\asmr\RJ1\e01.wav
  static final RegExp _fileProgressRe = RegExp(
    r'(?:正在处理[（(][^）)]*，|Processing [（(][^）)]*[）)] [（(]|正在翻译[（(])\s*(\d+)\s*/\s*(\d+)\s*[）)]\s*[：:]\s*(.+)$',
  );

  /// VAD 块进度（stdout print 输出），形如 VAD进度：3/120 块（2.5%）...
  static final RegExp _vadProgressRe = RegExp(r'(\d+)\s*/\s*(\d+)');

  /// 处理文件计数（stderr）：
  /// zh: 找到 3 个文件待处理 / en: Found 3 files to process
  static final RegExp _foundFilesRe = RegExp(
    r'找到\s*(\d+)\s*个文件待处理|Found\s*(\d+)\s+file',
    caseSensitive: false,
  );

  /// 无文件可处理（stderr）：
  /// zh: 未找到要处理的文件 / en: No files found to process
  static final RegExp _noFilesRe = RegExp(
    r'未找到要处理的文件|No files found to process',
    caseSensitive: false,
  );

  /// 解析 bat 内 infer.exe 的调用行（如
  /// `"%cpath%\\infer.exe" --device="cuda" --task="translate" %*`），
  /// 提取 exe 绝对路径与全部 `--参数`，以便**直调 exe 绕开 cmd**
  /// （bat 模式首选路径，见 buildCommand）。
  /// 官方 release 的所有 bat 均为此结构；解析失败返回 null（回退 wrapper）。
  _BatInvocation? _parseBatInvocation() {
    final file = File(config.scriptPath);
    if (!file.existsSync()) return null;
    final bytes = file.readAsBytesSync();
    final text = utf8.decode(bytes, allowMalformed: true);
    final batDir = p.dirname(config.scriptPath);
    final exeRe = RegExp(r'"([^"]*infer\.exe)"');
    final argRe = RegExp(r'--[\w-]+(?:="[^"]*"|=?\S+)?');
    for (final raw in text.split('\n')) {
      if (!raw.contains('infer.exe')) continue;
      final args = <String>[];
      for (final m in argRe.allMatches(raw)) {
        var s = m.group(0)!;
        final eq = s.indexOf('=');
        if (eq > 0 && s.length > eq + 1 && s.endsWith('"')) {
          // --key="value" → --key=value（去掉值两侧引号）
          s = s.substring(0, eq + 1) + s.substring(eq + 2, s.length - 1);
        }
        args.add(s);
      }
      if (args.isEmpty) continue;
      var exe = exeRe.firstMatch(raw)?.group(1) ?? '';
      if (exe.isEmpty) {
        final bare = RegExp(r'(?:\S+[/\\])?infer\.exe').firstMatch(raw);
        exe = bare?.group(0) ?? '';
      }
      if (exe.isEmpty) continue;
      exe = exe.replaceAll('%cpath%', batDir).replaceAll('%~dp0', batDir);
      // bat 内的路径分隔符固定为 `\`；归一为平台分隔符
      // （Windows 上等价，非 Windows 上便于测试验证）。
      exe = exe.replaceAll('\\', p.separator);
      if (!p.isAbsolute(exe)) exe = p.join(batDir, exe);
      return _BatInvocation(exe, args);
    }
    return null;
  }

  /// 从 ChickenRice 输出行解析进度：文件级进度（n/total + 文件名）优先，
  /// 其次 VAD 块进度（x/y）。文件级进度用于总进度，VAD 仅作次级刷新，
  /// 避免两者混用导致百分比回跳。
  void _parseProgress(
      String line, void Function(TranscribeProgress)? onProgress) {
    if (onProgress == null) return;
    final fileMatch = _fileProgressRe.firstMatch(line);
    if (fileMatch != null) {
      final done = int.tryParse(fileMatch.group(1)!);
      final total = int.tryParse(fileMatch.group(2)!);
      if (done == null || total == null || total <= 0) return;
      final raw = fileMatch.group(3)!.trim();
      final name = raw.split(RegExp(r'[\\/]')).last;
      onProgress(
          TranscribeProgress(done: done, total: total, currentFile: name));
      return;
    }
    final m = _vadProgressRe.firstMatch(line);
    if (m == null) return;
    final done = int.tryParse(m.group(1)!);
    final total = int.tryParse(m.group(2)!);
    if (done == null || total == null || total <= 0) return;
    onProgress(TranscribeProgress(done: done, total: total, currentFile: ''));
  }

  /// 解析处理文件数：找到 N 个文件待处理 → N；未找到要处理的文件 → 0。
  int? _parseFilesProcessed(String line, int? current) {
    if (current != null) return current;
    final found = _foundFilesRe.firstMatch(line);
    if (found != null) {
      return int.tryParse(found.group(1) ?? found.group(2) ?? '');
    }
    if (_noFilesRe.hasMatch(line)) return 0;
    return null;
  }
}

/// bat 内 infer.exe 调用解析结果：exe 绝对路径 + 参数列表。
class _BatInvocation {
  final String exePath;
  final List<String> args;

  _BatInvocation(this.exePath, this.args);
}