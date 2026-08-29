import 'package:path/path.dart' as p;

/// 音频 ↔ 字幕匹配的统一规则。
///
/// [NavidromeOrganizer]（歌词内嵌/侧车生成）、[SubtitleGapDetector]
/// （AI 翻译缺口检测）与 [VerifyService]（产物校验）共用本类，
/// 避免各自维护一套匹配规则导致「整理用 A 规则、校验用 B 规则」。
///
/// 匹配优先级：
/// 1. **相对路径**：字幕去掉扩展名后的相对路径与音频相对路径精确匹配，
///    同时支持两种命名（`disc1/01.vtt` → key `disc1/01`；
///    `disc1/01.wav.vtt` → key `disc1/01.wav`）。
///    `disc1/01.vtt` 只绑定 `disc1/` 下的音频，不会串到 `disc2/01.wav`。
/// 2. **basename 回退**：仅当音频 basename（去扩展名）在整个作品中唯一、
///    且候选字幕的 basename key 在全部字幕中同样唯一时才允许，
///    兼容异目录/扁平目录字幕。`disc1/01.wav` 与 `disc2/01.wav` 并存时，
///    `01.vtt` 不会绑定到其中任何一个（视为无字幕）。
class SubtitleMatcher {
  /// [audioPaths]/[subtitlePaths] 为作品内全部音频与字幕文件的路径
  /// （调用方负责按扩展名过滤；字幕与音频可不在同一目录）。
  SubtitleMatcher({
    required String sourceDir,
    required Iterable<String> audioPaths,
    required Iterable<String> subtitlePaths,
  }) : _sourceDir = p.normalize(sourceDir) {
    for (final audio in audioPaths) {
      final stem = _stem(p.basename(audio));
      _audioStemCount[stem] = (_audioStemCount[stem] ?? 0) + 1;
    }
    for (final subtitle in subtitlePaths) {
      final rel = _relOf(subtitle);
      final relKey = _withoutExtension(rel);
      final baseKey = _stem(p.basename(subtitle));
      _subsByRelKey.putIfAbsent(relKey, () => []).add(subtitle);
      _subsByBaseKey.putIfAbsent(baseKey, () => []).add(subtitle);
    }
  }

  final String _sourceDir;

  /// 字幕 relKey（去扩展名的相对路径，小写）→ 字幕路径
  final Map<String, List<String>> _subsByRelKey = {};

  /// 字幕 basename（去扩展名，小写）→ 字幕路径
  final Map<String, List<String>> _subsByBaseKey = {};

  /// 音频 basename（去扩展名，小写）→ 出现次数
  final Map<String, int> _audioStemCount = {};

  /// 与 [audioPath] 绑定的字幕路径（可能多个：同名 .lrc 与 .vtt 并存）。
  /// `.lrc` 恒排在 `.vtt` 前（整理器以 lrc 优先）。
  List<String> subtitlesFor(String audioPath) {
    final rel = _relOf(audioPath);
    final results = <String>[];

    // 1. 相对路径精确匹配：字幕命名可能带音频扩展名（foo.mp3.vtt）或不带（foo.vtt）
    results.addAll(_subsByRelKey[_withoutExtension(rel)] ?? const []);
    results.addAll(_subsByRelKey[rel] ?? const []);
    if (results.isNotEmpty) return _sorted(results);

    // 2. basename 回退：音频 stem 与候选字幕 key 在各自集合中都唯一才绑定
    final stem = _stem(p.basename(audioPath));
    if ((_audioStemCount[stem] ?? 0) == 1) {
      final byStem = _subsByBaseKey[stem];
      if (byStem != null && byStem.length == 1) {
        results.addAll(byStem);
      } else {
        // 字幕 stem 不唯一时不回退；但「音频全名」（如 01.wav）命名的字幕
        // （foo.wav.vtt 形式）仍可尝试一次唯一性回退
        final byFullName = _subsByBaseKey[p.basename(audioPath).toLowerCase()];
        if (byFullName != null && byFullName.length == 1) {
          results.addAll(byFullName);
        }
      }
    }
    return _sorted(results);
  }

  /// 音频是否已有绑定字幕（缺口检测判据）。
  bool hasSubtitle(String audioPath) => subtitlesFor(audioPath).isNotEmpty;

  List<String> _sorted(List<String> paths) {
    final unique = paths.toSet().toList();
    unique.sort((a, b) {
      final aLrc = a.toLowerCase().endsWith('.lrc') ? 0 : 1;
      final bLrc = b.toLowerCase().endsWith('.lrc') ? 0 : 1;
      if (aLrc != bLrc) return aLrc - bLrc;
      return a.compareTo(b);
    });
    return unique;
  }

  String _relOf(String path) =>
      p.relative(path, from: _sourceDir).toLowerCase().replaceAll('\\', '/');

  static String _withoutExtension(String path) =>
      p.withoutExtension(path).toLowerCase();

  static String _stem(String basename) =>
      p.basenameWithoutExtension(basename).toLowerCase();
}
