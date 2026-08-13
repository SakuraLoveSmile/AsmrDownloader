/// VTT 字幕转 LRC 歌词。
///
/// 输入为 WebVTT 字幕（asmr.one 的音轨字幕即此格式，实测样例）：
///
///     WEBVTT
///
///     1
///     00:00:00.900 --> 00:00:05.000
///     深入舔耳特化型智能性爱人偶 即将启动
///
/// 输出 LRC：
///
///     [00:00.90]深入舔耳特化型智能性爱人偶 即将启动
///
/// - 每个 cue 取开始时间，毫秒保留两位
/// - 分钟数 = 小时*60 + 分钟（长音轨可超过 59 分钟）
/// - 多行 cue 文本合并为一行（空格连接）
/// - 跳过 WEBVTT 头 / NOTE / STYLE / REGION / cue 编号 / 空行 / 空文本
/// - 无有效 cue 时返回 null（调用方静默跳过，不阻断整理）
library;

/// 匹配 cue 时间行：HH:MM:SS.mmm --> ...（小时可省略、毫秒分隔符兼容逗号）
final _cueTimingRegExp = RegExp(
  r'^(?:(\d{1,2}):)?(\d{2}):(\d{2})[.,](\d{1,3})\s+-->',
);

/// 跳过 VTT 头部/区块行（大小写不敏感前缀匹配）
final _headerRegExp = RegExp(
  r'^(WEBVTT|NOTE|STYLE|REGION)\b',
  caseSensitive: false,
);

/// 把 VTT 字幕内容转换为 LRC 文本；无有效 cue 返回 null。
String? vttToLrc(String vttContent) {
  final lines = vttContent.split(RegExp(r'\r?\n'));
  final lrcLines = <String>[];

  var i = 0;
  while (i < lines.length) {
    final line = lines[i].trim();
    i++;

    // 跳过空行、头部、区块声明、cue 编号行
    if (line.isEmpty ||
        _headerRegExp.hasMatch(line) ||
        !_cueTimingRegExp.hasMatch(line)) {
      continue;
    }

    // 收集该 cue 的文本行（直到空行或下一个时间行）
    final textLines = <String>[];
    while (i < lines.length) {
      final textLine = lines[i].trim();
      if (textLine.isEmpty || _cueTimingRegExp.hasMatch(textLine)) break;
      textLines.add(textLine);
      i++;
    }

    final text = textLines.join(' ');
    if (text.isEmpty) continue;

    lrcLines.add(_formatTimeLine(line, text));
  }

  if (lrcLines.isEmpty) return null;
  return lrcLines.join('\n');
}

/// 解析 cue 时间行并生成 [mm:ss.xx]文本 行
String _formatTimeLine(String timingLine, String text) {
  final match = _cueTimingRegExp.firstMatch(timingLine)!;
  final h = int.parse(match.group(1) ?? '0');
  final m = int.parse(match.group(2)!);
  final s = int.parse(match.group(3)!);
  // 毫秒按小数秒处理：'9' → 900ms，'90' → 900ms，'900' → 900ms
  final ms = int.parse(match.group(4)!.padRight(3, '0').substring(0, 3));

  final totalMs = h * 3600000 + m * 60000 + s * 1000 + ms;
  final mm = totalMs ~/ 60000;
  final ss = (totalMs % 60000) ~/ 1000;
  final xx = (totalMs % 1000) ~/ 10;

  return '[${_twoDigits(mm)}:${_twoDigits(ss)}.${_twoDigits(xx)}]$text';
}

String _twoDigits(int v) => v.toString().padLeft(2, '0');
