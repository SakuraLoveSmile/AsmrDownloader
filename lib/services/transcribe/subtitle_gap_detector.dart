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
  '.flv',
  '.wmv',
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

    // 单次遍历同时收集音轨与字幕文件名 key。
    // （旧实现对每个音轨都全量重扫一遍目录判字幕，O(N×M) 同步 I/O，
    // 音轨多时点击「生成字幕」主 isolate 会明显卡顿。）
    final audios = <File>[];
    final subtitleKeys = <String>{};
    for (final file in _allFiles(sourceDir)) {
      final name = p.basename(file.path).toLowerCase();
      final ext = p.extension(name);
      if (audioExt.contains(ext)) {
        audios.add(file);
      } else if (subExt.contains(ext)) {
        subtitleKeys.add(name.substring(0, name.length - ext.length));
      }
    }

    for (final audio in audios) {
      if (!_hasSubtitleKey(subtitleKeys, audio)) {
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
    var count = 0;
    for (final file in _allFiles(sourceDir)) {
      if (audioExt.contains(p.extension(file.path).toLowerCase())) count++;
    }
    return count;
  }

  /// 用单次遍历收集的 [subtitleKeys] 判断 [audio] 是否已有同名字幕。
  ///
  /// 覆盖两种命名：
  /// - `foo.lrc` / `foo.vtt` / `foo.srt`（key = stem，即 "foo"）
  /// - `foo.mp3.lrc` / `foo.mp3.vtt`（key = stem + 音频扩展名，如 "foo.mp3"）
  ///
  /// 字幕与音轨不要求同目录（按文件名匹配，与整理逻辑一致）；
  /// stem 比较不区分大小写。
  static bool _hasSubtitleKey(Set<String> subtitleKeys, File audio) {
    final basename = p.basename(audio.path).toLowerCase();
    final stem = p.basenameWithoutExtension(basename);
    if (subtitleKeys.contains(stem)) return true;
    // targets 由 kAudioExtensions 泛化生成，保证视频音轨（如 foo.mp4）的
    // `foo.mp4.vtt` 也能被识别为已有字幕，避免重复翻译。
    for (final ext in kAudioExtensions) {
      if (subtitleKeys.contains('$stem${ext.toLowerCase()}')) return true;
    }
    return false;
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
