import 'dart:io';

import 'package:asmr_downloader/services/transcribe/subtitle_matcher.dart';
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
    if (!Directory(sourceDir).existsSync()) return const [];

    final audioExt = {for (final e in audioExtensions) e.toLowerCase()};
    final subExt = {for (final e in subtitleExtensions) e.toLowerCase()};

    // 单次遍历同时收集音轨与字幕路径，匹配交给统一的 [SubtitleMatcher]。
    // （旧实现对每个音轨都全量重扫一遍目录判字幕，O(N×M) 同步 I/O，
    // 音轨多时点击「生成字幕」主 isolate 会明显卡顿。）
    final audioPaths = <String>[];
    final subtitlePaths = <String>[];
    for (final file in _allFiles(sourceDir)) {
      final name = p.basename(file.path).toLowerCase();
      final ext = p.extension(name);
      if (audioExt.contains(ext)) {
        audioPaths.add(file.path);
      } else if (subExt.contains(ext)) {
        subtitlePaths.add(file.path);
      }
    }
    return _filterMissing(sourceDir, audioPaths, subtitlePaths)
        .map(File.new)
        .toList();
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

  /// [findMissingSubtitleTracks] 的异步版本：用异步目录遍历代替
  /// listSync，不阻塞调用方 isolate（UI 链路应使用本方法，
  /// 否则多作品/多音轨时主线程会明显卡顿）。
  static Future<List<File>> findMissingSubtitleTracksAsync(
    String sourceDir, {
    List<String> audioExtensions = kAudioExtensions,
    List<String> subtitleExtensions = kSubtitleExtensions,
  }) async {
    if (!await Directory(sourceDir).exists()) return const [];

    final audioExt = {for (final e in audioExtensions) e.toLowerCase()};
    final subExt = {for (final e in subtitleExtensions) e.toLowerCase()};

    final audioPaths = <String>[];
    final subtitlePaths = <String>[];
    await for (final file in _allFilesAsync(sourceDir)) {
      final name = p.basename(file.path).toLowerCase();
      final ext = p.extension(name);
      if (audioExt.contains(ext)) {
        audioPaths.add(file.path);
      } else if (subExt.contains(ext)) {
        subtitlePaths.add(file.path);
      }
    }
    return _filterMissing(sourceDir, audioPaths, subtitlePaths)
        .map(File.new)
        .toList();
  }

  /// 用统一的 [SubtitleMatcher] 过滤出缺少字幕的音轨路径
  /// （相对路径优先，basename 全作品唯一时才回退）。
  static List<String> _filterMissing(
    String sourceDir,
    List<String> audioPaths,
    List<String> subtitlePaths,
  ) {
    final matcher = SubtitleMatcher(
      sourceDir: sourceDir,
      audioPaths: audioPaths,
      subtitlePaths: subtitlePaths,
    );
    return [
      for (final audio in audioPaths)
        if (!matcher.hasSubtitle(audio)) audio,
    ];
  }

  /// [countAudioFiles] 的异步版本（不阻塞调用方 isolate）。
  static Future<int> countAudioFilesAsync(
    String sourceDir, {
    List<String> audioExtensions = kAudioExtensions,
  }) async {
    if (!await Directory(sourceDir).exists()) return 0;
    final audioExt = {for (final e in audioExtensions) e.toLowerCase()};
    var count = 0;
    await for (final file in _allFilesAsync(sourceDir)) {
      if (audioExt.contains(p.extension(file.path).toLowerCase())) count++;
    }
    return count;
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

  /// 异步递归遍历（与 [_allFiles] 同规则：跳过隐藏目录、不跟随软链）。
  static Stream<File> _allFilesAsync(String dir) async* {
    final stack = <Directory>[Directory(dir)];
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      try {
        await for (final entity in current.list(followLinks: false)) {
          if (entity is Directory) {
            final name = p.basename(entity.path);
            if (name.startsWith('.')) continue;
            stack.add(entity);
          } else if (entity is File) {
            yield entity;
          }
        }
      } catch (_) {
        continue;
      }
    }
  }
}
