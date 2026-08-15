import 'dart:io';

import 'package:asmr_downloader/services/transcribe/vtt_converter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _vtt = '''WEBVTT

1
00:00:00.900 --> 00:00:05.000
深入舔耳特化型智能性爱人偶 即将启动

2
00:00:05.000 --> 00:00:10.000
第二句台词
''';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vtt_test');
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  File touch(String rel, [String content = '']) {
    final f = File(p.join(dir.path, rel));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
    return f;
  }

  test('foo.vtt 可转换（无同名 lrc），foo.mp3.vtt 保留音频扩展名', () {
    touch('ex01.杂谈.wav.vtt', _vtt);
    touch('ex02.杂谈.mp3.vtt', _vtt);
    final found = VttConverter.findConvertibleVtts(dir.path);
    expect(found.map((f) => p.basename(f.path)).toSet(),
        {'ex01.杂谈.wav.vtt', 'ex02.杂谈.mp3.vtt'});
  });

  test('已有同名 lrc 的 vtt 不转换', () {
    touch('ex01.杂谈.wav.vtt', _vtt);
    touch('ex01.杂谈.wav.lrc', '[00:00.90]人工字幕');
    touch('ex02.mp3.vtt', _vtt);
    touch('ex02.mp3.lrc', '[00:00.90]人工字幕');
    final found = VttConverter.findConvertibleVtts(dir.path);
    expect(found, isEmpty);
  });

  test('目录不存在返回空', () {
    expect(VttConverter.findConvertibleVtts('/nope'), isEmpty);
    expect(VttConverter.convertAll('/nope'), completion(0));
  });

  test('convertAll 生成 lrc 并返回数量，重复转换幂等', () async {
    touch('a.wav.vtt', _vtt);
    touch('b.wav.vtt', _vtt);
    expect(await VttConverter.convertAll(dir.path), 2);
    expect(File(p.join(dir.path, 'a.wav.lrc')).existsSync(), isTrue);
    expect(File(p.join(dir.path, 'b.wav.lrc')).existsSync(), isTrue);

    // 已有 lrc 后不再重复转换
    expect(await VttConverter.convertAll(dir.path), 0);
  });

  test('无有效 cue 的 vtt 跳过（返回 0）', () async {
    touch('c.wav.vtt', 'WEBVTT\n\nNOTE nothing\n');
    expect(await VttConverter.convertAll(dir.path), 0);
    expect(File(p.join(dir.path, 'c.wav.lrc')).existsSync(), isFalse);
  });
}
