/// ChickenRice（Faster-Whisper-TransWithAI-ChickenRice）联动的配置模型。
class ChickenRiceConfig {
  /// ChickenRice 启动脚本（.bat / .cmd）或 infer.exe 的绝对路径。
  ///
  /// 选 .bat 时：翻译/转录与设备由所选 bat 决定（bat 自带
  /// `--device=...` 与任务设定），[device]/[task] 不生效；
  /// 选 .exe 时：全部参数由本配置拼接。
  final String scriptPath;

  /// 计算设备：`auto` / `cuda` / `cpu`（amd/rocm/hip 归一为 cuda）。
  /// 仅 exe 模式生效；bat 模式由 bat 决定。
  final String device;

  /// Whisper 任务：`translate`（中文翻译，默认）/ `transcribe`（原文转录）。
  /// 仅 exe 模式生效；bat 模式由 bat 决定。
  final String task;

  /// 输出字幕格式（逗号分隔），默认只输出 lrc（与 Navidrome 整理链路对齐）。
  /// 仅 exe 模式生效。
  final String subFormats;

  /// 处理的音频后缀（逗号分隔）。仅 exe 模式生效。
  final String audioSuffixes;

  /// 是否覆盖已存在的字幕（默认 false：已存在则跳过，天然增量）
  final bool overwrite;

  /// 模型目录（默认 `models`，即 exe 所在目录下的 models）。仅 exe 模式生效。
  final String modelNameOrPath;

  const ChickenRiceConfig({
    this.scriptPath = '',
    this.device = 'auto',
    this.task = 'translate',
    this.subFormats = 'lrc',
    this.audioSuffixes = 'wav,flac,mp3,m4a,aac,ogg',
    this.overwrite = false,
    this.modelNameOrPath = 'models',
  });

  bool get isConfigured => scriptPath.isNotEmpty;

  /// 是否为批处理脚本（.bat/.cmd）：经 `cmd.exe /c call` 调用，
  /// 且任务/设备由 bat 自身决定。
  bool get isBat {
    final lower = scriptPath.toLowerCase();
    return lower.endsWith('.bat') || lower.endsWith('.cmd');
  }

  /// 是否为 infer.exe 直调。
  bool get isExe => scriptPath.toLowerCase().endsWith('.exe');

  ChickenRiceConfig copyWith({
    String? scriptPath,
    String? device,
    String? task,
    String? subFormats,
    String? audioSuffixes,
    bool? overwrite,
    String? modelNameOrPath,
  }) {
    return ChickenRiceConfig(
      scriptPath: scriptPath ?? this.scriptPath,
      device: device ?? this.device,
      task: task ?? this.task,
      subFormats: subFormats ?? this.subFormats,
      audioSuffixes: audioSuffixes ?? this.audioSuffixes,
      overwrite: overwrite ?? this.overwrite,
      modelNameOrPath: modelNameOrPath ?? this.modelNameOrPath,
    );
  }
}

/// 一次转录运行的结果。
class TranscribeResult {
  final bool success;
  final int exitCode;
  final String? error;

  const TranscribeResult({
    required this.success,
    required this.exitCode,
    this.error,
  });
}
