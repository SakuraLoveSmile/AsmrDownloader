import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:asmr_downloader/utils/log.dart';
import 'package:taglib_dart/taglib_dart.dart';

/// 给音频文件写标签（title/artist/album/albumArtist/track）。
/// - mp3 / flac：使用 taglib_dart 写 ID3v2 / Vorbis comment
/// - wav：写 'id3 ' chunk（USLT 歌词/APIC 封面，TagLib/Navidrome/ffmpeg 原生读取）
///   与 LIST/INFO chunk（INAM/IART/IPRD/IPRT，老播放器兼容，纯 Dart 实现）
/// - 其他格式：跳过
class AudioTagWriter {
  static const _audioExtensions = ['wav', 'flac', 'mp3'];

  static bool isAudioFile(String path) {
    final ext = path.split('.').last.toLowerCase();
    return _audioExtensions.contains(ext);
  }

  /// 写标签（不抛出，避免阻断整理流程）。
  /// 返回 true 表示目标状态已达成（文件已带标签跳过或写入成功）；仅真正失败返回 false。
  /// [lyrics] 内嵌歌词（LRC 文本，mp3→USLT / flac→LYRICS / wav→id3 chunk USLT）
  /// [coverBytes] 内嵌封面（mp3→APIC / flac→PICTURE / wav→id3 chunk APIC）
  /// [year] 发行年份（mp3→TYER / flac→YEAR / wav→TYER）
  /// [genre] 流派（mp3→TCON / flac→GENRE / wav→TCON）
  /// [forceWavRewrite] 仅影响 wav：已有本工具写入的 'id3 ' chunk 时先剥离再重写
  /// （补齐新歌词/封面；mp3/flac 本来就整体重写）。第三方 LIST/INFO 标签仍不覆盖。
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
    bool forceWavRewrite = false,
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
              genre: genre,
              forceWavRewrite: forceWavRewrite);
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
  /// [forceWavRewrite] 为 true 时先剥离本工具写的 'id3 ' 与带 INAM 的 LIST/INFO，
  /// 再走正常流程重新打完整标签（校验修复路径）；仅含第三方 INAM 的 wav 仍跳过。
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
    bool forceWavRewrite = false,
  }) async {
    final file = File(filePath);
    if (!await _isValidWav(file)) {
      Log.warning('not a valid wav file, skip tags: $filePath');
      return false;
    }

    // 强制重写：先剥离本工具写入的标签 chunk，让下方正常流程重新打完整标签；
    // 剥离后下方扫描不再命中跳过分支。
    if (forceWavRewrite && await _hasId3Chunk(file)) {
      await _stripOwnTagChunks(file);
      Log.info('wav force rewrite: stripped own tag chunks: $filePath');
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

  /// 读取 wav 的内嵌歌词/封面状态（扫描 'id3 ' chunk 的 USLT/APIC 帧）。
  /// 文件不存在/无 'id3 ' chunk 时返回 (false, false)。
  static Future<({bool lyrics, bool cover})> readWavEmbed(
      String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return (lyrics: false, cover: false);
    final raf = await file.open();
    try {
      var offset = 12;
      while (offset + 8 <= await raf.length()) {
        await raf.setPosition(offset);
        final chunkHeader = Uint8List.fromList(await raf.read(8));
        if (chunkHeader.length < 8) break;
        final chunkId = String.fromCharCodes(chunkHeader.sublist(0, 4));
        final chunkSize = _leUint32(chunkHeader.sublist(4, 8));
        if (chunkId == 'id3 ' || chunkId == 'ID3 ') {
          // 必须 await：直接 return 未来完成的 future 时，
          // finally 会在其内部 IO 未完成时先行 close（pending 操作异常）
          return await _scanId3Frames(raf, offset + 8, chunkSize);
        }
        offset += 8 + chunkSize + (chunkSize.isOdd ? 1 : 0);
      }
      return (lyrics: false, cover: false);
    } finally {
      await raf.close();
    }
  }

  /// 判断 wav 是否带「非本工具写入」的第三方音乐标签：
  /// LIST/INFO 含 INAM（曲名）且无 'id3 ' chunk。
  /// 本工具不会覆盖此类文件；校验服务据此把内嵌缺失归为不可修复。
  static Future<bool> isThirdPartyTaggedWav(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return false;
    final raf = await file.open();
    try {
      final scan = await _scanWavTagChunks(raf);
      return !scan.hasId3 && scan.hasListInam;
    } finally {
      await raf.close();
    }
  }

  /// 检查 wav 是否已带 'id3 ' chunk（本工具写入的内嵌标签标志）。
  static Future<bool> _hasId3Chunk(File file) async {
    final raf = await file.open();
    try {
      final scan = await _scanWavTagChunks(raf);
      return scan.hasId3;
    } finally {
      await raf.close();
    }
  }

  /// 强制重写 wav 前剥离本工具写入的标签 chunk：
  /// - 'id3 ' chunk（内嵌歌词/封面所在）
  /// - 带 INAM 的 LIST/INFO chunk（本工具写的老播放器兼容标签）
  /// 重建文件内容并更新 RIFF size（文件长度 - 8）；
  /// 第三方仅含技术元数据（ICRD/ISFT）的 LIST/INFO 保留不动。
  static Future<void> _stripOwnTagChunks(File file) async {
    final bytes = await file.readAsBytes();
    if (bytes.length < 12) return;
    final builder = BytesBuilder();
    builder.add(bytes.sublist(0, 12)); // RIFF/WAVE 头
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final size =
          _leUint32(Uint8List.fromList(bytes.sublist(offset + 4, offset + 8)));
      final total = 8 + size + (size.isOdd ? 1 : 0);
      if (offset + total > bytes.length) {
        // 畸形 chunk 尺寸：保留剩余数据，避免截断文件
        builder.add(bytes.sublist(offset));
        break;
      }
      var keep = true;
      if (chunkId == 'id3 ' || chunkId == 'ID3 ') {
        keep = false;
      } else if (chunkId == 'LIST' &&
          offset + 12 <= bytes.length &&
          String.fromCharCodes(bytes.sublist(offset + 8, offset + 12)) ==
              'INFO' &&
          _listInfoBytesHasInam(bytes, offset + 12, size - 4)) {
        keep = false;
      }
      if (keep) builder.add(bytes.sublist(offset, offset + total));
      offset += total;
    }
    final newBytes = builder.toBytes();
    if (newBytes.length == bytes.length) return; // 没有需要剥离的 chunk
    final riffSize = newBytes.length - 8;
    newBytes[4] = riffSize & 0xFF;
    newBytes[5] = (riffSize >> 8) & 0xFF;
    newBytes[6] = (riffSize >> 16) & 0xFF;
    newBytes[7] = (riffSize >> 24) & 0xFF;
    await file.writeAsBytes(newBytes);
  }

  /// 检查内存中 LIST/INFO chunk 数据区（[start] 起、长度 [length]）是否含 INAM。
  static bool _listInfoBytesHasInam(Uint8List bytes, int start, int length) {
    if (length < 8) return false;
    var pos = start;
    final end = start + length;
    while (pos + 8 <= end && pos + 8 <= bytes.length) {
      final subId = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final subSize =
          _leUint32(Uint8List.fromList(bytes.sublist(pos + 4, pos + 8)));
      if (subId == 'INAM') return true;
      pos += 8 + subSize + (subSize.isOdd ? 1 : 0);
    }
    return false;
  }

  /// 扫描 ID3v2 tag 数据区内的帧头（4 字节帧 id + size），判定是否含 USLT/APIC 帧。
  /// [start] 指向 'id3 ' chunk 数据区起点（'ID3' 标识）；[chunkSize] 为数据区长度。
  /// ID3v2.3 帧大小为大端 32 位，ID3v2.4 为 synchsafe；两种都识别。
  /// 注意：不关闭传入的 raf（由调用方管理）
  static Future<({bool lyrics, bool cover})> _scanId3Frames(
      RandomAccessFile raf, int start, int chunkSize) async {
    if (chunkSize < 10) return (lyrics: false, cover: false);
    await raf.setPosition(start);
    final header = Uint8List.fromList(await raf.read(10));
    if (header.length < 10 ||
        String.fromCharCodes(header.sublist(0, 3)) != 'ID3') {
      return (lyrics: false, cover: false);
    }
    final version = header[3];
    final tagSize = ((header[6] & 0x7F) << 21) |
        ((header[7] & 0x7F) << 14) |
        ((header[8] & 0x7F) << 7) |
        (header[9] & 0x7F);
    // tag 数据区终点：tag 头声明的大小可能带 padding，且不超过 chunk 边界
    var end = start + 10 + tagSize;
    if (end > start + chunkSize) end = start + chunkSize;

    var lyrics = false;
    var cover = false;
    var pos = start + 10;
    while (pos + 10 <= end) {
      await raf.setPosition(pos);
      final frameHeader = Uint8List.fromList(await raf.read(10));
      if (frameHeader.length < 10) break;
      final frameId = String.fromCharCodes(frameHeader.sublist(0, 4));
      if (frameId.startsWith('\u0000')) break; // padding 区
      final frameSize = version == 4
          ? ((frameHeader[4] & 0x7F) << 21) |
              ((frameHeader[5] & 0x7F) << 14) |
              ((frameHeader[6] & 0x7F) << 7) |
              (frameHeader[7] & 0x7F)
          : _beUint32(frameHeader.sublist(4, 8));
      if (frameId == 'USLT') lyrics = true;
      if (frameId == 'APIC') cover = true;
      if (lyrics && cover) return (lyrics: true, cover: true);
      pos += 10 + frameSize;
    }
    return (lyrics: lyrics, cover: cover);
  }

  static int _beUint32(Uint8List bytes) =>
      (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];

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
        final listType =
            String.fromCharCodes(Uint8List.fromList(await raf.read(4)));
        if (listType == 'INFO') {
          hasListInfo = true;
          hasListInam =
              await _listInfoHasInam(raf, offset + 12, chunkSize - 4) ||
                  hasListInam;
        }
      }
      offset += 8 + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }
    return (hasId3: hasId3, hasListInfo: hasListInfo, hasListInam: hasListInam);
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

  static Uint8List _uint32Le(int value) => Uint8List.fromList([
        value & 0xFF,
        (value >> 8) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 24) & 0xFF,
      ]);
}
