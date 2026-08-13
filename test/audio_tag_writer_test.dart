import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:asmr_downloader/services/organize/audio_tag_writer.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造最小合法 wav：RIFF header + fmt chunk + data chunk
Uint8List buildMinimalWav() {
  final fmt = Uint8List.fromList([
    // PCM, mono, 8000Hz, 16bit
    0x01, 0x00, // audio format
    0x01, 0x00, // channels
    0x40, 0x1F, 0x00, 0x00, // sample rate 8000
    0x80, 0x3E, 0x00, 0x00, // byte rate 16000
    0x02, 0x00, // block align
    0x10, 0x00, // bits per sample
  ]);
  final data = List<int>.filled(16, 0); // 16 bytes 静音
  final fmtChunk = <int>[
    ...'fmt '.codeUnits,
    ..._u32le(fmt.length),
    ...fmt,
  ];
  final dataChunk = <int>[
    ...'data'.codeUnits,
    ..._u32le(data.length),
    ...data,
  ];
  final body = Uint8List.fromList([...fmtChunk, ...dataChunk]);
  final wav = Uint8List.fromList([
    ...'RIFF'.codeUnits,
    ..._u32le(4 + body.length),
    ...'WAVE'.codeUnits,
    ...body,
  ]);
  return wav;
}

Uint8List _u32le(int v) => Uint8List.fromList(
    [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

String _ascii(Uint8List bytes, int start, int len) =>
    String.fromCharCodes(bytes.sublist(start, start + len));

/// 读取 wav 文件，返回 'LIST' chunk 内容（含 'INFO' 标识）
Map<String, String>? _readListInfo(File file) {
  final bytes = file.readAsBytesSync();
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = _ascii(bytes, offset, 4);
    final size = (bytes[offset + 4] |
            (bytes[offset + 5] << 8) |
            (bytes[offset + 6] << 16) |
            (bytes[offset + 7] << 24)) &
        0x7FFFFFFF;
    if (id == 'LIST' && offset + 8 + size <= bytes.length) {
      final listType = _ascii(bytes, offset + 8, 4);
      if (listType == 'INFO') {
        final result = <String, String>{};
        var pos = offset + 12;
        final end = offset + 8 + size;
        while (pos + 8 <= end) {
          final subId = _ascii(bytes, pos, 4);
          final subSize = (bytes[pos + 4] |
                  (bytes[pos + 5] << 8) |
                  (bytes[pos + 6] << 16) |
                  (bytes[pos + 7] << 24)) &
              0x7FFFFFFF;
          final value = utf8.decode(bytes.sublist(pos + 8, pos + 8 + subSize));
          result[subId] = value;
          pos += 8 + subSize + (subSize.isOdd ? 1 : 0);
        }
        return result;
      }
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  return null;
}

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('wav_tag_test');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  test('wav 写 LIST INFO 标签：title/artist/album/albumartist/track', () async {
    final wavFile = File('${tmpDir.path}/01_测试音轨.wav')
      ..writeAsBytesSync(buildMinimalWav());

    final ok = await AudioTagWriter.writeTags(
      wavFile.path,
      title: '01_测试音轨',
      artist: '空心菜館',
      album: '测试专辑',
      albumArtist: '古都ことり',
      track: '1',
    );

    expect(ok, true);

    final info = _readListInfo(wavFile);
    expect(info, isNotNull);
    expect(info!['INAM'], '01_测试音轨');
    expect(info['IART'], '空心菜館');
    expect(info['IPRD'], '测试专辑');
    expect(info['IPRT'], '1');
  });

  test('wav 写标签后 RIFF size 更新且文件可读', () async {
    final wavFile = File('${tmpDir.path}/track.wav')
      ..writeAsBytesSync(buildMinimalWav());
    final origLen = wavFile.lengthSync();

    await AudioTagWriter.writeTags(
      wavFile.path,
      title: 't',
      artist: 'a',
      album: 'al',
      albumArtist: 'aa',
      track: '1',
    );

    // RIFF size = 文件长度 - 8
    final bytes = wavFile.readAsBytesSync();
    final riffSize = (bytes[4] |
            (bytes[5] << 8) |
            (bytes[6] << 16) |
            (bytes[7] << 24)) &
        0x7FFFFFFF;
    expect(riffSize + 8, bytes.length);
    expect(bytes.length, greaterThan(origLen));

    // 原有 data chunk 内容未被破坏
    expect(_ascii(bytes, 0, 4), 'RIFF');
    expect(_ascii(bytes, 8, 4), 'WAVE');
    expect(_ascii(bytes, 12, 4), 'fmt ');
    expect(_ascii(bytes, 12 + 8 + 16, 4), 'data');
  });

  test('wav 写内嵌歌词（USLT 帧）和内嵌封面（APIC 帧）', () async {
    final wavFile = File('${tmpDir.path}/track.wav')
      ..writeAsBytesSync(buildMinimalWav());
    final cover = Uint8List.fromList(List.filled(200, 1));

    final ok = await AudioTagWriter.writeTags(
      wavFile.path,
      title: 't',
      artist: 'a',
      album: 'al',
      albumArtist: 'aa',
      track: '1',
      lyrics: '[00:01.00]测试歌词\n[00:02.00]第二行',
      coverBytes: cover,
    );

    expect(ok, true);

    final bytes = wavFile.readAsBytesSync();
    final asStr = String.fromCharCodes(bytes);
    expect(asStr.contains('USLT'), true);
    expect(asStr.contains('APIC'), true);
    // 歌词内容以 UTF-16 LE 存在
    final lyricsUtf16 = [
      0xFF,
      0xFE,
      ...'[00:01.00]测试歌词'.codeUnits.expand((u) => [u & 0xFF, u >> 8]),
    ];
    expect(bytes, containsAllInOrder(lyricsUtf16));
  });

  test('wav 写发行年份（TYER）和流派（TCON）帧', () async {
    final wavFile = File('${tmpDir.path}/track.wav')
      ..writeAsBytesSync(buildMinimalWav());

    final ok = await AudioTagWriter.writeTags(
      wavFile.path,
      title: 't',
      artist: 'a',
      album: 'al',
      albumArtist: 'aa',
      track: '1',
      year: '2026',
      genre: 'ASMR; 舔耳',
    );

    expect(ok, true);

    final bytes = wavFile.readAsBytesSync();
    final asStr = String.fromCharCodes(bytes);
    expect(asStr.contains('TYER'), true);
    expect(asStr.contains('TCON'), true);
    // 年份内容以 UTF-16 LE 存在
    final yearUtf16 = [
      0xFF,
      0xFE,
      ...'2026'.codeUnits.expand((u) => [u & 0xFF, u >> 8]),
    ];
    expect(bytes, containsAllInOrder(yearUtf16));
  });

  test('幂等：已有 LIST INFO chunk 时跳过（不重复追加）', () async {
    final wavFile = File('${tmpDir.path}/track.wav')
      ..writeAsBytesSync(buildMinimalWav());

    await AudioTagWriter.writeTags(
      wavFile.path,
      title: 't',
      artist: 'a',
      album: 'al',
      albumArtist: 'aa',
      track: '1',
    );
    final lenAfterFirst = wavFile.lengthSync();

    final ok = await AudioTagWriter.writeTags(
      wavFile.path,
      title: 't2',
      artist: 'a2',
      album: 'al2',
      albumArtist: 'aa2',
      track: '2',
    );

    expect(ok, false); // 已存在 LIST 时跳过
    expect(wavFile.lengthSync(), lenAfterFirst);
    // 标签内容保持第一次写入的
    final info = _readListInfo(wavFile);
    expect(info!['INAM'], 't');
  });

  test('非 wav 文件不写', () async {
    final txtFile = File('${tmpDir.path}/a.txt')..writeAsStringSync('x');
    final ok = await AudioTagWriter.writeTags(
      txtFile.path,
      title: 't',
      artist: 'a',
      album: 'al',
      albumArtist: 'aa',
    );
    expect(ok, false);
  });

  test('非法 wav（无 RIFF 头）不写', () async {
    final badFile = File('${tmpDir.path}/bad.wav')
      ..writeAsBytesSync(List.filled(100, 0));
    final ok = await AudioTagWriter.writeTags(
      badFile.path,
      title: 't',
      artist: 'a',
      album: 'al',
      albumArtist: 'aa',
    );
    expect(ok, false);
  });
}
