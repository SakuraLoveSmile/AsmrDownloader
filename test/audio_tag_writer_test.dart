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

/// 构造 LIST chunk（listType 如 'INFO'/'adtl'），子 chunk 为 id -> 值
Uint8List buildListChunk(String listType, Map<String, String> subs) {
  final subChunks = <int>[];
  subs.forEach((id, value) {
    final data = utf8.encode(value);
    subChunks
      ..addAll(id.codeUnits)
      ..addAll(_u32le(data.length))
      ..addAll(data)
      ..addAll(List.filled(data.length.isOdd ? 1 : 0, 0));
  });
  return Uint8List.fromList([
    ...'LIST'.codeUnits,
    ..._u32le(subChunks.length + 4), // +4 是 listType 标识
    ...listType.codeUnits,
    ...subChunks,
  ]);
}

/// 在最小合法 wav 末尾追加自定义 chunk 并重建 RIFF size
Uint8List appendChunkToWav(Uint8List chunk) {
  final base = buildMinimalWav();
  final oldSize =
      (base[4] | (base[5] << 8) | (base[6] << 16) | (base[7] << 24)) &
          0x7FFFFFFF;
  return Uint8List.fromList([
    ...base.sublist(0, 4),
    ..._u32le(oldSize + chunk.length),
    ...base.sublist(8),
    ...chunk,
  ]);
}

/// 构造带指定 LIST/INFO 子 chunk 的合法 wav（如 ICRD/ISFT 技术元数据）
Uint8List buildWavWithListInfo(Map<String, String> subs) =>
    appendChunkToWav(buildListChunk('INFO', subs));

/// 统计文件中指定 4 字节 chunk id 的数量
int countChunks(File file, String chunkId) {
  final bytes = file.readAsBytesSync();
  var count = 0;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = _ascii(bytes, offset, 4);
    final size = (bytes[offset + 4] |
            (bytes[offset + 5] << 8) |
            (bytes[offset + 6] << 16) |
            (bytes[offset + 7] << 24)) &
        0x7FFFFFFF;
    if (id == chunkId) count++;
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  return count;
}

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
    final riffSize =
        (bytes[4] | (bytes[5] << 8) | (bytes[6] << 16) | (bytes[7] << 24)) &
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
    // USLT/APIC 描述字段必须含 null 终止符（BOM ff fe + 00 00），
    // 否则解析器会把后续数据误读为描述，封面/歌词读取失败
    // USLT：描述终止符后紧跟歌词的 UTF-16 BOM
    expect(bytes, containsAllInOrder([0xFF, 0xFE, 0x00, 0x00, 0xFF, 0xFE]));
    // APIC：描述终止符后紧跟封面数据（测试用 0x01 填充）
    expect(bytes, containsAllInOrder([0xFF, 0xFE, 0x00, 0x00, 0x01, 0x01]));
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

    expect(ok, true); // 已有标签跳过视为成功
    expect(wavFile.lengthSync(), lenAfterFirst);
    // 标签内容保持第一次写入的
    final info = _readListInfo(wavFile);
    expect(info!['INAM'], 't');
  });

  test('带 ICRD/ISFT 技术元数据的 wav：照常写入 id3，不追加第二个 LIST INFO', () async {
    // 模拟 asmr.one 广播 WAV（如 舔耳ONLY音轨 目录下的文件）
    final wavFile = File('${tmpDir.path}/broadcast.wav')
      ..writeAsBytesSync(buildWavWithListInfo({
        'ICRD': '2026-04-18T13:14:55+09:00',
        'ISFT': 'Adobe Audition 25.0 (Windows)',
      }));

    final ok = await AudioTagWriter.writeTags(
      wavFile.path,
      title: '双耳舔舐',
      artist: '空心菜館',
      album: '测试专辑',
      albumArtist: '古都ことり',
      track: '1',
    );

    expect(ok, true);
    // id3 chunk 写入成功
    expect(countChunks(wavFile, 'id3 '), 1);
    // LIST 仍只有一个（不追加第二个 LIST INFO）
    expect(countChunks(wavFile, 'LIST'), 1);
    // 原有技术元数据保留，未混入 INAM
    final info = _readListInfo(wavFile);
    expect(info, isNotNull);
    expect(info!['ICRD'], '2026-04-18T13:14:55+09:00');
    expect(info['ISFT'], 'Adobe Audition 25.0 (Windows)');
    expect(info.containsKey('INAM'), false);
    // RIFF size = 文件长 - 8
    final bytes = wavFile.readAsBytesSync();
    final riffSize =
        (bytes[4] | (bytes[5] << 8) | (bytes[6] << 16) | (bytes[7] << 24)) &
            0x7FFFFFFF;
    expect(riffSize + 8, bytes.length);
  });

  test('带技术元数据的 wav：重复写入幂等跳过', () async {
    final wavFile = File('${tmpDir.path}/broadcast2.wav')
      ..writeAsBytesSync(buildWavWithListInfo({'ICRD': '2026-04-18'}));

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

    expect(ok, true); // 已有 id3 chunk 跳过视为成功
    expect(wavFile.lengthSync(), lenAfterFirst);
  });

  test('LIST INFO 已含 INAM：视为已有音乐标签，跳过', () async {
    final wavFile = File('${tmpDir.path}/tagged.wav')
      ..writeAsBytesSync(buildWavWithListInfo({
        'INAM': '已有标题',
        'IART': '某人',
      }));
    final len = wavFile.lengthSync();

    final ok = await AudioTagWriter.writeTags(
      wavFile.path,
      title: 't',
      artist: 'a',
      album: 'al',
      albumArtist: 'aa',
      track: '1',
    );

    expect(ok, true); // 已有 INAM 跳过视为成功
    expect(wavFile.lengthSync(), len);
    expect(countChunks(wavFile, 'id3 '), 0);
  });

  test('LIST 类型非 INFO（adtl）：正常写入 id3 与 LIST INFO', () async {
    final wavFile = File('${tmpDir.path}/adtl.wav')
      ..writeAsBytesSync(
          appendChunkToWav(buildListChunk('adtl', {'labl': 'cue1'})));

    final ok = await AudioTagWriter.writeTags(
      wavFile.path,
      title: 't',
      artist: 'a',
      album: 'al',
      albumArtist: 'aa',
      track: '1',
    );

    expect(ok, true);
    expect(countChunks(wavFile, 'id3 '), 1);
    // 原有 adtl LIST + 新写的 INFO LIST
    expect(countChunks(wavFile, 'LIST'), 2);
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

  group('readWavEmbed', () {
    test('含 USLT/APIC 帧判定正确（无标签/仅歌词/仅封面/两者）', () async {
      final bare = File('${tmpDir.path}/bare.wav')
        ..writeAsBytesSync(buildMinimalWav());
      expect(await AudioTagWriter.readWavEmbed(bare.path),
          (lyrics: false, cover: false));

      final lyricsOnly = File('${tmpDir.path}/lyrics.wav')
        ..writeAsBytesSync(buildMinimalWav());
      await AudioTagWriter.writeTags(
        lyricsOnly.path,
        title: 't',
        artist: 'a',
        album: 'al',
        albumArtist: 'aa',
        lyrics: '[00:01.00]测试歌词',
      );
      expect(await AudioTagWriter.readWavEmbed(lyricsOnly.path),
          (lyrics: true, cover: false));

      final coverOnly = File('${tmpDir.path}/cover.wav')
        ..writeAsBytesSync(buildMinimalWav());
      await AudioTagWriter.writeTags(
        coverOnly.path,
        title: 't',
        artist: 'a',
        album: 'al',
        albumArtist: 'aa',
        coverBytes: Uint8List.fromList(List.filled(20, 1)),
      );
      expect(await AudioTagWriter.readWavEmbed(coverOnly.path),
          (lyrics: false, cover: true));

      final both = File('${tmpDir.path}/both.wav')
        ..writeAsBytesSync(buildMinimalWav());
      await AudioTagWriter.writeTags(
        both.path,
        title: 't',
        artist: 'a',
        album: 'al',
        albumArtist: 'aa',
        lyrics: '[00:01.00]测试歌词',
        coverBytes: Uint8List.fromList(List.filled(20, 1)),
      );
      expect(await AudioTagWriter.readWavEmbed(both.path),
          (lyrics: true, cover: true));
    });

    test('第三方 LIST/INFO INAM（无 id3）→ 无内嵌标签且判定为第三方', () async {
      final wavFile = File('${tmpDir.path}/third.wav')
        ..writeAsBytesSync(buildWavWithListInfo({'INAM': '他人标题'}));
      expect(await AudioTagWriter.readWavEmbed(wavFile.path),
          (lyrics: false, cover: false));
      expect(await AudioTagWriter.isThirdPartyTaggedWav(wavFile.path), true);
    });

    test('本工具写入 id3 后不再是「第三方标签」', () async {
      final wavFile = File('${tmpDir.path}/ours.wav')
        ..writeAsBytesSync(buildMinimalWav());
      await AudioTagWriter.writeTags(
        wavFile.path,
        title: 't',
        artist: 'a',
        album: 'al',
        albumArtist: 'aa',
      );
      expect(await AudioTagWriter.isThirdPartyTaggedWav(wavFile.path), false);
    });
  });

  group('forceWavRewrite', () {
    test('已有 id3 chunk 剥离后重写：新歌词/封面生效且仅一个 id3 chunk、RIFF size 正确', () async {
      final wavFile = File('${tmpDir.path}/rewrite.wav')
        ..writeAsBytesSync(buildMinimalWav());
      await AudioTagWriter.writeTags(
        wavFile.path,
        title: '旧标题',
        artist: 'a',
        album: 'al',
        albumArtist: 'aa',
        track: '1',
      );

      final ok = await AudioTagWriter.writeTags(
        wavFile.path,
        title: '新标题',
        artist: 'a2',
        album: 'al2',
        albumArtist: 'aa2',
        track: '1',
        lyrics: '[00:01.00]新歌词',
        coverBytes: Uint8List.fromList(List.filled(30, 2)),
        forceWavRewrite: true,
      );

      expect(ok, true);
      expect(countChunks(wavFile, 'id3 '), 1);
      expect(countChunks(wavFile, 'LIST'), 1);
      // 旧标签被剥离，LIST/INFO 与 id3 都按新值重建
      final info = _readListInfo(wavFile);
      expect(info!['INAM'], '新标题');
      expect(await AudioTagWriter.readWavEmbed(wavFile.path),
          (lyrics: true, cover: true));
      // 新歌词内容已写入（UTF-16 LE）
      final bytes = wavFile.readAsBytesSync();
      final lyricsUtf16 = [
        0xFF,
        0xFE,
        ...'[00:01.00]新歌词'.codeUnits.expand((u) => [u & 0xFF, u >> 8]),
      ];
      expect(bytes, containsAllInOrder(lyricsUtf16));
      // RIFF size = 文件长 - 8
      final riffSize =
          (bytes[4] | (bytes[5] << 8) | (bytes[6] << 16) | (bytes[7] << 24)) &
              0x7FFFFFFF;
      expect(riffSize + 8, bytes.length);
    });

    test('无 id3 的 wav：force 与普通写入一致（不剥离也不跳过）', () async {
      final wavFile = File('${tmpDir.path}/clean.wav')
        ..writeAsBytesSync(buildMinimalWav());
      final ok = await AudioTagWriter.writeTags(
        wavFile.path,
        title: 't',
        artist: 'a',
        album: 'al',
        albumArtist: 'aa',
        lyrics: '[00:01.00]歌词',
        forceWavRewrite: true,
      );
      expect(ok, true);
      expect(countChunks(wavFile, 'id3 '), 1);
      expect(await AudioTagWriter.readWavEmbed(wavFile.path),
          (lyrics: true, cover: false));
    });

    test('第三方 LIST/INFO INAM 仍不覆盖（force 也不写）', () async {
      final wavFile = File('${tmpDir.path}/third_force.wav')
        ..writeAsBytesSync(buildWavWithListInfo({'INAM': '他人标题'}));
      final len = wavFile.lengthSync();

      final ok = await AudioTagWriter.writeTags(
        wavFile.path,
        title: 't',
        artist: 'a',
        album: 'al',
        albumArtist: 'aa',
        lyrics: 'x',
        forceWavRewrite: true,
      );

      expect(ok, true); // 已有他人标签跳过视为成功
      expect(wavFile.lengthSync(), len);
      expect(await AudioTagWriter.isThirdPartyTaggedWav(wavFile.path), true);
      expect(await AudioTagWriter.readWavEmbed(wavFile.path),
          (lyrics: false, cover: false));
    });
  });
}
