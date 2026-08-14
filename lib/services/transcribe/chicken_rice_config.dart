/// ChickenRice（Faster-Whisper-TransWithAI-ChickenRice）联动的配置模型。
class ChickenRiceConfig {
  /// infer.exe（或 bat）的绝对路径
  final String exePath;

  /// 计算设备：`auto` / `cuda` / `cpu`（amd/rocm/hip 归一为 cuda）
  final String device;

  /// Whisper 任务：`translate`（中文翻译，默认）/ `transcribe`（原文转录）
  final String task;

  /// 输出字幕格式（逗号分隔），默认只输出 lrc（与 Navidrome 整理链路对齐）
  final String subFormats;

  /// 处理的音频后缀（逗号分隔）
  final String audioSuffixes;

  /// 是否覆盖已存在的字幕（默认 false：已存在则跳过，天然增量）
  final bool overwrite;

  /// 模型目录（默认 `models`，即 exe 所在目录下的 models）
  final String modelNameOrPath;

  const ChickenRiceConfig({
    this.exePath = '',
    this.device = 'auto',
    this.task = 'translate',
    this.subFormats = 'lrc',
    this.audioSuffixes = 'wav,flac,mp3,m4a,aac,ogg',
    this.overwrite = false,
    this.modelNameOrPath = 'models',
  });

  bool get isConfigured => exePath.isNotEmpty;

  ChickenRiceConfig copyWith({
    String? exePath,
    String? device,
    String? task,
    String? subFormats,
    String? audioSuffixes,
    bool? overwrite,
    String? modelNameOrPath,
  }) {
    return ChickenRiceConfig(
      exePath: exePath ?? this.exePath,
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
