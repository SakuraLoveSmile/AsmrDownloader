import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:asmr_downloader/utils/log.dart';
import 'package:taglib_dart/taglib_dart.dart';

/// 给音频文件写标签（title/artist/album/albumArtist/track）。
/// - mp3 / flac：使用 taglib_dart 写 ID3v2 / Vorbis comment
/// - wav：手写 LIST/INFO chunk（INAM/IART/IPRD/IPRT，纯 Dart 实现）
/// - 其他格式：跳过
class AudioTagWriter {
  static const _audioExtensions = ['wav', 'flac', 'mp3'];

  static bool isAudioFile(String path) {
    final ext = path.split('.').last.toLowerCase();
    return _audioExtensions.contains(ext);
  }

  /// 写标签，失败返回 false（不抛出，避免阻断整理流程）
  static Future<bool> writeTags(
    String filePath, {
    required String title,
    required String artist,
    required String album,
    required String albumArtist,
    String? track,
  }) async {
    try {
      final ext = filePath.split('.').last.toLowerCase();
      switch (ext) {
        case 'wav':
          return _writeWavTags(filePath,
              title: title,
              artist: artist,
              album: album,
              albumArtist: albumArtist,
              track: track);
        case 'mp3':
        case 'flac':
          return _writeTaglibTags(filePath,
              title: title,
              artist: artist,
              album: album,
              albumArtist: albumArtist,
              track: track);
        default:
          return false;
      }
    } catch (e) {
      Log.warning('write tags failed: $filePath\n' 'error: $e');
      return false;
    }
  }

  /// mp3/flac 用 taglib_dart 写标签
  static Future<bool> _writeTaglibTags(
    String filePath, {
    required String title,
    required String artist,
    required String album,
    required String albumArtist,
    String? track,
  }) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final format = filePath.endsWith('.flac')
        ? Format.flac
        : Format.mp3;
    final audioFile = AudioFile(bytes, format)
      ..setTitle(title)
      ..setArtist(artist)
      ..setAlbum(album)
      ..setAlbumArtist(albumArtist)
      ..setTrack(track);
    await file.writeAsBytes(audioFile.save());
    return true;
  }

  /// wav 写 LIST/INFO chunk。
  /// 文件末尾追加 LIST chunk（data chunk 之后合法），并更新 RIFF size。
  /// 若文件已存在 LIST INFO chunk 则跳过（避免重复追加）。
  static Future<bool> _writeWavTags(
    String filePath, {
    required String title,
    required String artist,
    required String album,
    required String albumArtist,
    String? track,
  }) async {
    final file = File(filePath);
    if (!await _isValidWav(file)) {
      Log.warning('not a valid wav file, skip tags: $filePath');
      return false;
    }

    final raf = await file.open(mode: FileMode.append);
    try {
      // 检查是否已有 LIST chunk（读文件头 chunk 列表）
      if (await _hasListInfoChunk(raf)) {
        Log.info('wav already has LIST INFO chunk, skip: $filePath');
        return false;
      }

      // 构造 LIST INFO chunk：
      // 'LIST' + size + 'INFO' + 若干 ('INAM'|'IART'|'IPRD'|'IPRT' + size + data)
      final builder = BytesBuilder();
      final subChunks = BytesBuilder();
      void addSubChunk(String id, String value) {
        if (value.isEmpty) return;
        final data = utf8.encode(value);
        subChunks
          ..add(id.codeUnits)
          ..add(_uint32Le(data.length))
          ..add(data)
          // chunk 数据奇数长度时补 1 字节
          ..add(List.filled(data.length.isOdd ? 1 : 0, 0));
      }

      addSubChunk('INAM', title);
      addSubChunk('IART', artist);
      addSubChunk('IPRD', album);
      addSubChunk('IPRT', track ?? '');

      final subData = subChunks.toBytes();
      builder
        ..add('LIST'.codeUnits)
        ..add(_uint32Le(subData.length + 4)) // +4 是 'INFO' 标识
        ..add('INFO'.codeUnits)
        ..add(subData);
      final listChunk = builder.toBytes();

      // 更新 RIFF size（偏移 4）：加 LIST chunk 大小
      final riffSize = await _readUint32Le(raf, 4);
      await raf.setPosition(4);
      await raf.writeFrom(_uint32Le(riffSize + listChunk.length));

      // 追加 LIST chunk 到文件末尾
      await raf.setPosition(await raf.length());
      await raf.writeFrom(listChunk);

      Log.info('wav tags written: $filePath');
      return true;
    } finally {
      await raf.close();
    }
  }

  /// 检查是否为合法 wav（RIFF/WAVE 头）
  static Future<bool> _isValidWav(File file) async {
    final raf = await file.open();
    try {
      final header = Uint8List.fromList(await raf.read(12));
      return header.length == 12 &&
          String.fromCharCodes(header.sublist(0, 4)) == 'RIFF' &&
          String.fromCharCodes(header.sublist(8, 12)) == 'WAVE';
    } finally {
      await raf.close();
    }
  }

  /// 遍历 RIFF chunk 列表，检查是否已有 LIST INFO chunk
  /// 注意：不关闭传入的 raf（由调用方管理）
  static Future<bool> _hasListInfoChunk(RandomAccessFile raf) async {
    var offset = 12;
    while (offset + 8 <= await raf.length()) {
      await raf.setPosition(offset);
      final chunkHeader = Uint8List.fromList(await raf.read(8));
      if (chunkHeader.length < 8) break;
      final chunkId = String.fromCharCodes(chunkHeader.sublist(0, 4));
      final chunkSize = _leUint32(chunkHeader.sublist(4, 8));
      if (chunkId == 'LIST') {
        await raf.setPosition(offset + 8);
        final listType = String.fromCharCodes(
            Uint8List.fromList(await raf.read(4)));
        if (listType == 'INFO') return true;
      }
      offset += 8 + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }
    return false;
  }

  static Future<int> _readUint32Le(RandomAccessFile raf, int position) async {
    await raf.setPosition(position);
    final bytes = Uint8List.fromList(await raf.read(4));
    if (bytes.length < 4) return 0;
    return _leUint32(bytes);
  }

  static int _leUint32(Uint8List bytes) =>
      bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);

  static Uint8List _uint32Le(int value) =>
      Uint8List.fromList([
        value & 0xFF,
        (value >> 8) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 24) & 0xFF,
      ]);
}
