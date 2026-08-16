import 'dart:io';

import 'package:asmr_downloader/services/transcribe/subtitle_gap_detector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory testBase;
  late Directory workDir;

  setUp(() {
    testBase = Directory.systemTemp.createTempSync('subtitle_gap_test');
    workDir = Directory(p.join(testBase.path, 'RJ12345678'))
      ..createSync(recursive: true);
  });

  tearDown(() {
    testBase.deleteSync(recursive: true);
  });

  void audio(String name) => File(p.join(workDir.path, name))
      .writeAsBytesSync(List.filled(100, 1));
  void sub(String name) => File(p.join(workDir.path, name))
      .writeAsBytesSync(List.filled(10, 2));

  test('无字幕的音轨全部需要翻译', () {
    audio('e01.wav');
    audio('e02.flac');
    final missing =
        SubtitleGapDetector.findMissingSubtitleTracks(workDir.path);
    expect(missing.length, 2);
  });

  test('有同名 .lrc 或 .vtt 的音轨被排除', () {
    audio('e01.wav');
    audio('e02.flac');
    sub('e01.lrc'); // e01 有字幕
    final missing =
        SubtitleGapDetector.findMissingSubtitleTracks(workDir.path);
    expect(missing.map((f) => p.basename(f.path)).toList(), ['e02.flac']);
  });

  test('兼容 foo.mp3.vtt 命名（带音频扩展名）', () {
    audio('e01.wav');
    audio('e02.flac');
    sub('e02.flac.vtt'); // 带音频扩展名的字幕
    final missing =
        SubtitleGapDetector.findMissingSubtitleTracks(workDir.path);
    expect(missing.map((f) => p.basename(f.path)).toList(), ['e01.wav']);
  });

  test('.srt 也被视为已有字幕', () {
    audio('e01.wav');
    sub('e01.srt');
    final missing =
        SubtitleGapDetector.findMissingSubtitleTracks(workDir.path);
    expect(missing, isEmpty);
  });

  test('视频音轨：foo.mp4.vtt 视为已有字幕（视频 stem 匹配）', () {
    audio('e01.mp4');
    sub('e01.mp4.vtt'); // 视频音轨带扩展名的字幕
    final missing =
        SubtitleGapDetector.findMissingSubtitleTracks(workDir.path);
    expect(missing, isEmpty);
  });

  test('视频音轨无字幕时列入缺口（flv/wmv 在支持列表内）', () {
    audio('e01.flv');
    audio('e02.wmv');
    final missing =
        SubtitleGapDetector.findMissingSubtitleTracks(workDir.path);
    expect(missing.map((f) => p.basename(f.path)).toSet(),
        {'e01.flv', 'e02.wmv'});
  });

  test('kAudioExtensions 覆盖官方 bat 的全部后缀', () {
    expect(
      kAudioExtensions,
      containsAll(['.wma', '.mp4', '.mkv', '.avi', '.mov', '.webm',
          '.flv', '.wmv']),
    );
  });

  test('递归扫描子目录中的音频与字幕', () {
    final subDir = Directory(p.join(workDir.path, '音声'))..createSync();
    File(p.join(subDir.path, 'e01.wav')).writeAsBytesSync(List.filled(100, 1));
    File(p.join(subDir.path, 'e01.wav.vtt'))
        .writeAsBytesSync(List.filled(10, 1));
    File(p.join(workDir.path, '特典', 'ex01.wav'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(List.filled(100, 1));
    final missing =
        SubtitleGapDetector.findMissingSubtitleTracks(workDir.path);
    expect(missing.length, 1); // 只有 ex01.wav 缺字幕
    expect(p.basename(missing.first.path), 'ex01.wav');
  });

  test('目录不存在时返回空', () {
    expect(
      SubtitleGapDetector.findMissingSubtitleTracks(
          p.join(testBase.path, 'not_exist')),
      isEmpty,
    );
  });

  test('扩展名大小写不敏感', () {
    audio('e01.WAV');
    sub('e01.lrc');
    final missing =
        SubtitleGapDetector.findMissingSubtitleTracks(workDir.path);
    expect(missing, isEmpty);
  });

  group('异步版本（UI 链路用，不阻塞主线程）', () {
    test('与同步版本结果一致（含子目录/多命名）', () async {
      audio('e01.wav');
      audio('e02.flac');
      sub('e01.lrc');
      sub('e02.flac.vtt');
      final subDir = Directory(p.join(workDir.path, '特典'))
        ..createSync();
      File(p.join(subDir.path, 'ex01.wav'))
          .writeAsBytesSync(List.filled(100, 1));

      final syncNames = SubtitleGapDetector.findMissingSubtitleTracks(
              workDir.path)
          .map((f) => p.basename(f.path))
          .toList()
        ..sort();
      final asyncNames =
          (await SubtitleGapDetector.findMissingSubtitleTracksAsync(
                  workDir.path))
              .map((f) => p.basename(f.path))
              .toList()
            ..sort();
      expect(asyncNames, syncNames);
      expect(asyncNames, ['ex01.wav']);
    });

    test('countAudioFilesAsync 与同步版本一致', () async {
      audio('e01.wav');
      audio('e02.flac');
      sub('e01.lrc');
      expect(await SubtitleGapDetector.countAudioFilesAsync(workDir.path),
          SubtitleGapDetector.countAudioFiles(workDir.path));
    });

    test('目录不存在时返回空', () async {
      expect(
        await SubtitleGapDetector.findMissingSubtitleTracksAsync(
            p.join(testBase.path, 'not_exist')),
        isEmpty,
      );
    });
  });
}
