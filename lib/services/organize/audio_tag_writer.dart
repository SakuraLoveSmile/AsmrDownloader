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

  /// 写标签（不抛出，避免阻断整理流程）。
  /// 返回 true 表示目标状态已达成（文件已带标签跳过或写入成功）；仅真正失败返回 false。
  /// [lyrics] 内嵌歌词（LRC 文本，mp3→USLT / flac→LYRICS；wav 不支持）
  /// [coverBytes] 内嵌封面（mp3→APIC / flac→PICTURE；wav 不支持）
  /// [year] 发行年份（mp3→TYER / flac→YEAR / wav→TYER）
  /// [genre] 流派（mp3→TCON / flac→GENRE / wav→TCON）
  static Future<bool> writeTags(
    String filePath, {
    required String title,
    required String artist,
    required String album,
    required String albumArtist,
    String? track,
    String? lyrics,
    Uint8List? coverBytes,
    String? year,
    String? genre,
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
              track: track,
              lyrics: lyrics,
              coverBytes: coverBytes,
              year: year,
              genre: genre);
        case 'mp3':
        case 'flac':
          return _writeTaglibTags(filePath,
              title: title,
              artist: artist,
              album: album,
              albumArtist: albumArtist,
              track: track,
              lyrics: lyrics,
              coverBytes: coverBytes,
              year: year,
              genre: genre);
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
    String? lyrics,
    Uint8List? coverBytes,
    String? year,
    String? genre,
  }) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final format = filePath.endsWith('.flac') ? Format.flac : Format.mp3;
    final audioFile = AudioFile(bytes, format)
      ..setTitle(title)
      ..setArtist(artist)
      ..setAlbum(album)
      ..setAlbumArtist(albumArtist)
      ..setTrack(track)
      ..setYear(year)
      ..setGenre(genre);
    if (lyrics != null && lyrics.isNotEmpty) {
      audioFile.setLyric(lyrics);
    }
    if (coverBytes != null && coverBytes.isNotEmpty) {
      audioFile.setCover(coverBytes);
    }
    await file.writeAsBytes(audioFile.save());
    return true;
  }

  /// wav 写标签：
  /// 1. ID3v2 chunk（'id3 '，TagLib/Navidrome/ffmpeg 原生读取）— 歌词 USLT / 封面 APIC
  /// 2. LIST/INFO chunk（老播放器兼容）；文件原本已带 LIST/INFO 时不追加第二个
  /// 文件末尾追加 chunk 并更新 RIFF size。
  /// 幂等：已有 'id3 ' chunk 或 LIST/INFO 含 INAM（曲名）视为已打音乐标签则跳过；
  /// 只带 ICRD/ISFT 等技术元数据的 LIST/INFO 照常写入。
  static Future<bool> _writeWavTags(
    String filePath, {
    required String title,
    required String artist,
    required String album,
    required String albumArtist,
    String? track,
    String? lyrics,
    Uint8List? coverBytes,
    String? year,
    String? genre,
  }) async {
    final file = File(filePath);
    if (!await _isValidWav(file)) {
      Log.warning('not a valid wav file, skip tags: $filePath');
      return false;
    }

    final raf = await file.open(mode: FileMode.append);
    try {
      // 已有音乐标签（本工具写的 'id3 ' chunk，或他人写的 LIST/INFO 曲名 INAM）
      // 则跳过；只带 ICRD/ISFT 等技术元数据的 LIST/INFO 不视为已打标签
      final scan = await _scanWavTagChunks(raf);
      if (scan.hasId3 || scan.hasListInam) {
        Log.info('wav already has music tags, skip: $filePath');
        return true;
      }

      final chunks = BytesBuilder();

      // ID3v2 chunk：歌词（USLT 帧）+ 封面（APIC 帧）+ 基础字段
      // RIFF 规范要求 chunk 数据偶对齐，奇数长度补 1 字节
      final id3 = _buildId3v2(
        title: title,
        artist: artist,
        album: album,
        albumArtist: albumArtist,
        track: track,
        lyrics: lyrics,
        coverBytes: coverBytes,
        year: year,
        genre: genre,
      );
      chunks
        ..add('id3 '.codeUnits)
        ..add(_uint32Le(id3.length))
        ..add(id3)
        ..add(List.filled(id3.length.isOdd ? 1 : 0, 0));

      // LIST INFO chunk（老播放器兼容）；
      // 文件原本已带 LIST/INFO（如 ICRD/ISFT 技术元数据）时不追加第二个，
      // 避免部分老播放器只读第一个 LIST 导致看不到标签
      if (!scan.hasListInfo) {
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
        chunks
          ..add('LIST'.codeUnits)
          ..add(_uint32Le(subData.length + 4)) // +4 是 'INFO' 标识
          ..add('INFO'.codeUnits)
          ..add(subData);
      }

      final newChunks = chunks.toBytes();

      // 更新 RIFF size（偏移 4）：加新 chunk 总大小
      final riffSize = await _readUint32Le(raf, 4);
      await raf.setPosition(4);
      await raf.writeFrom(_uint32Le(riffSize + newChunks.length));

      // 追加到文件末尾
      await raf.setPosition(await raf.length());
      await raf.writeFrom(newChunks);

      Log.info('wav tags written: $filePath');
      return true;
    } finally {
      await raf.close();
    }
  }

  /// 构造 ID3v2.3 tag（用于 WAV 的 'id3 ' chunk）
  /// 文本帧 UTF-16 编码（v2.3 兼容性最好的中文编码）
  static Uint8List _buildId3v2({
    required String title,
    required String artist,
    required String album,
    required String albumArtist,
    String? track,
    String? lyrics,
    Uint8List? coverBytes,
    String? year,
    String? genre,
  }) {
    final frames = BytesBuilder();

    void addFrame(String id, List<int> data) {
      frames
        ..add(id.codeUnits)
        ..add(_uint32Be(data.length))
        ..add([0x00, 0x00]) // frame flags
        ..add(data);
    }

    void addTextFrame(String id, String text) {
      if (text.isEmpty) return;
      addFrame(id, [0x01, ..._utf16Le(text)]); // 0x01 = UTF-16
    }

    addTextFrame('TIT2', title);
    addTextFrame('TPE1', artist);
    addTextFrame('TALB', album);
    addTextFrame('TPE2', albumArtist);
    addTextFrame('TRCK', track ?? '');
    addTextFrame('TYER', year ?? '');
    addTextFrame('TCON', genre ?? '');

    // USLT 歌词帧：encoding + lang(3) + 描述(UTF-16 空，含 null 终止符) + 歌词
    // 描述字段缺少终止符会导致解析器把歌词内容误读为描述（见 ffprobe 验证）
    if (lyrics != null && lyrics.isNotEmpty) {
      final data = <int>[
        0x01,
        ...'eng'.codeUnits,
        ..._utf16LeTerminated(''),
        ..._utf16Le(lyrics),
      ];
      addFrame('USLT', data);
    }

    // APIC 封面帧：encoding + mime + \0 + 类型(3=cover front) + 描述(含终止符) + 图片
    // 描述字段必须 null 终止，否则解析器找不到图片数据起始位置，封面读取失败
    if (coverBytes != null && coverBytes.isNotEmpty) {
      final mime = _imageMime(coverBytes);
      final data = <int>[
        0x01,
        ...mime.codeUnits,
        0x00,
        0x03, // picture type: cover (front)
        ..._utf16LeTerminated(''),
        ...coverBytes,
      ];
      addFrame('APIC', data);
    }

    final frameBytes = frames.toBytes();
    return Uint8List.fromList([
      ...'ID3'.codeUnits,
      0x03, 0x00, // version 2.3.0
      0x00, // flags
      ..._synchsafe(frameBytes.length),
      ...frameBytes,
    ]);
  }

  /// UTF-16 LE 编码（含 BOM），Dart String 内部即 UTF-16
  static List<int> _utf16Le(String text) {
    final bytes = <int>[0xFF, 0xFE];
    for (final unit in text.codeUnits) {
      bytes
        ..add(unit & 0xFF)
        ..add((unit >> 8) & 0xFF);
    }
    return bytes;
  }

  /// UTF-16 LE 编码 + null 终止符（ID3v2.3 中 USLT/APIC 的描述字段要求）
  static List<int> _utf16LeTerminated(String text) => [
        ..._utf16Le(text),
        0x00,
        0x00,
      ];

  static String _imageMime(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    return 'image/jpeg';
  }

  /// ID3v2 tag 大小：synchsafe 32-bit（每字节只取低 7 位）
  static List<int> _synchsafe(int value) => [
        (value >> 21) & 0x7F,
        (value >> 14) & 0x7F,
        (value >> 7) & 0x7F,
        value & 0x7F,
      ];

  static Uint8List _uint32Be(int value) => Uint8List.fromList([
        (value >> 24) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 8) & 0xFF,
        value & 0xFF,
      ]);

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

  /// 扫描 RIFF chunk，返回标签 chunk 存在情况：
  /// - hasId3：已有 'id3 ' chunk（本工具写入的标志）
  /// - hasListInfo：已有 LIST/INFO chunk（可能只含 ICRD/ISFT 等技术元数据）
  /// - hasListInam：LIST/INFO 中含 INAM（曲名）子 chunk，即已被其他工具写过音乐标签
  /// 注意：不关闭传入的 raf（由调用方管理）
  static Future<({bool hasId3, bool hasListInfo, bool hasListInam})>
      _scanWavTagChunks(RandomAccessFile raf) async {
    var hasId3 = false;
    var hasListInfo = false;
    var hasListInam = false;
    var offset = 12;
    while (offset + 8 <= await raf.length()) {
      await raf.setPosition(offset);
      final chunkHeader = Uint8List.fromList(await raf.read(8));
      if (chunkHeader.length < 8) break;
      final chunkId = String.fromCharCodes(chunkHeader.sublist(0, 4));
      final chunkSize = _leUint32(chunkHeader.sublist(4, 8));
      if (chunkId == 'id3 ' || chunkId == 'ID3 ') {
        hasId3 = true;
      } else if (chunkId == 'LIST') {
        await raf.setPosition(offset + 8);
        final listType = String.fromCharCodes(
            Uint8List.fromList(await raf.read(4)));
        if (listType == 'INFO') {
          hasListInfo = true;
          hasListInam =
              await _listInfoHasInam(raf, offset + 12, chunkSize - 4) ||
              hasListInam;
        }
      }
      offset += 8 + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }
    return (
        hasId3: hasId3, hasListInfo: hasListInfo, hasListInam: hasListInam);
  }

  /// 检查 LIST/INFO chunk 数据区（offset+12 起、长度 [length]）是否含 INAM 子 chunk。
  /// 注意：不关闭传入的 raf（由调用方管理）
  static Future<bool> _listInfoHasInam(
      RandomAccessFile raf, int start, int length) async {
    if (length < 8) return false;
    var pos = start;
    final end = start + length;
    while (pos + 8 <= end) {
      await raf.setPosition(pos);
      final header = Uint8List.fromList(await raf.read(8));
      if (header.length < 8) break;
      final subId = String.fromCharCodes(header.sublist(0, 4));
      final subSize = _leUint32(header.sublist(4, 8));
      if (subId == 'INAM') return true;
      pos += 8 + subSize + (subSize.isOdd ? 1 : 0);
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
