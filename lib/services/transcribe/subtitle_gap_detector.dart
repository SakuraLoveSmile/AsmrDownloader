import 'dart:io';

import 'package:path/path.dart' as p;

/// 字幕扩展名（官方/本地字幕均视为「已有字幕」）。
///
/// 判据：只要某音轨存在同名 `.lrc` / `.vtt` / `.srt` 官方字幕，
/// 就视为「官方字幕可用」，不再调用 AI 翻译（避免浪费算力、避免覆盖官方字幕）。
/// 仅对没有任何字幕文件的音轨返回【需要 AI 翻译】。
const List<String> kSubtitleExtensions = ['.lrc', '.vtt', '.srt'];

/// 音频扩展名（ChickenRice 处理的文件格式）。
const List<String> kAudioExtensions = [
  '.wav',
  '.flac',
  '.mp3',
  '.m4a',
  '.aac',
  '.ogg',
  '.wma',
  '.mp4',
  '.mkv',
  '.avi',
  '.mov',
  '.webm',
];

/// 判断音轨是否需要 AI 生成字幕。
///
/// 判据（用户确认的简化方案）：
/// - 若已存在同名 `.lrc` / `.vtt` / `.srt` 字幕（含 `foo.mp3.vtt` 与 `foo.vtt` 两种命名），
///   则视为官方字幕可用，【跳过】AI 翻译；
/// - 否则需要 AI 翻译。
class SubtitleGapDetector {
  /// 返回指定目录下【缺少任何字幕】的音轨文件列表。
  ///
  /// [sourceDir] 作品目录（会被递归扫描）。
  /// 只统计格式在 [audioExtensions] 内的文件；
  /// 扩展名比较不区分大小写。
  static List<File> findMissingSubtitleTracks(
    String sourceDir, {
    List<String> audioExtensions = kAudioExtensions,
    List<String> subtitleExtensions = kSubtitleExtensions,
  }) {
    final result = <File>[];
    if (!Directory(sourceDir).existsSync()) return result;

    final audioExt = {for (final e in audioExtensions) e.toLowerCase()};
    final subExt = {for (final e in subtitleExtensions) e.toLowerCase()};

    for (final audio in _collectAudioFiles(sourceDir, audioExt)) {
      final basename = p.basename(audio.path);
      final stem = p.basenameWithoutExtension(basename);
      if (!_hasSubtitle(sourceDir, stem, subExt)) {
        result.add(audio);
      }
    }
    return result;
  }

  /// 返回指定目录下音轨文件总数（递归，扩展名不区分大小写）。
  static int countAudioFiles(
    String sourceDir, {
    List<String> audioExtensions = kAudioExtensions,
  }) {
    if (!Directory(sourceDir).existsSync()) return 0;
    final audioExt = {for (final e in audioExtensions) e.toLowerCase()};
    return _collectAudioFiles(sourceDir, audioExt).length;
  }

  /// 判断某个音频（按不带扩展名的 [stem]）是否已有同名字幕。
  ///
  /// 覆盖两种命名：
  /// - `foo.lrc` / `foo.vtt` / `foo.srt`（key = stem，即 "foo"）
  /// - `foo.mp3.lrc` / `foo.mp3.vtt`（key = stem + 音频扩展名，如 "foo.mp3"）
  ///
  /// 递归扫描 [sourceDir] 下所有文件进行匹配（字幕可能与被检音频不同目录，
  /// 与整理逻辑一致地用「文件名」而非「同目录」匹配）。
  static bool _hasSubtitle(String sourceDir, String stem, Set<String> subExt) {
    final targets = <String>{
      stem,
      '$stem.wav',
      '$stem.flac',
      '$stem.mp3',
      '$stem.m4a',
      '$stem.aac',
      '$stem.ogg',
      '$stem.wma',
    };
    // 需排除音频本体自身（同名不同扩展名可能被误判为字幕）
    for (final file in _allFiles(sourceDir)) {
      final name = p.basename(file.path).toLowerCase();
      final ext = p.extension(name);
      if (!subExt.contains(ext)) continue;
      final key = name.substring(0, name.length - ext.length);
      if (targets.contains(key)) return true;
    }
    return false;
  }

  static Iterable<File> _collectAudioFiles(
      String dir, Set<String> audioExt) sync* {
    for (final file in _allFiles(dir)) {
      if (audioExt.contains(p.extension(file.path).toLowerCase())) {
        yield file;
      }
    }
  }

  static Iterable<File> _allFiles(String dir) sync* {
    final stack = <Directory>[Directory(dir)];
    while (stack.isNotEmpty) {
      final dir2 = stack.removeLast();
      List<FileSystemEntity> children;
      try {
        children = dir2.listSync(followLinks: false);
      } catch (_) {
        continue;
      }
      for (final entity in children) {
        if (entity is Directory) {
          final name = p.basename(entity.path);
          // 跳过隐藏目录（如 .DS_Store、下载临时目录）
          if (name.startsWith('.')) continue;
          stack.add(entity);
        } else if (entity is File) {
          yield entity;
        }
      }
    }
  }
}
