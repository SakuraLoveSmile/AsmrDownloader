import 'dart:io';
import 'dart:typed_data';

import 'package:asmr_downloader/services/organize/audio_tag_writer.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:asmr_downloader/utils/vtt_to_lrc.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:path/path.dart' as p;

class OrganizeResult {
  final int copied;
  final int skipped;
  final int tagWriteFailures;

  const OrganizeResult({
    required this.copied,
    required this.skipped,
    this.tagWriteFailures = 0,
  });
}

/// 专辑目录名（`<sourceId> - <cvNames> - <title>`）最大码点数
const int kMaxAlbumDirChars = 80;

/// 专辑目录名最大 UTF-8 字节数（防 emoji 等 4 字节字符突破 macOS 255 字节组件限制）
const int kMaxAlbumDirUtf8Bytes = 240;

/// circle 目录名最大码点数
const int kMaxCircleDirChars = 50;

/// circle 目录名最大 UTF-8 字节数
const int kMaxCircleDirUtf8Bytes = 150;

/// 将下载的作品整理成 Navidrome 媒体库结构：
/// `<targetRoot>/<circleName>/<sourceId> - <cvNames> - <title>/<sourceId>/`
/// 音轨/字幕/歌词文件扁平化复制，保留原名；封面保存为 cover.jpg（Navidrome 自动识别）。
/// 目录名过长时按字符/字节上限智能截断（保留 sourceId，尾部加 …）。
class NavidromeOrganizer {
  /// 解析整理用的社团名。
  /// 汉化版作品的 circle 是汉化组名，需要跟踪到原版（original_workno）取真实社团名。
  /// [workInfo] 当前作品的 workInfo；[fallbackCircle] 当前作品返回的 circle 名
  /// [fetchWorkInfo] 按数字 id 拉取作品信息（可注入 mock 便于测试）
  static Future<String> resolveCircleName({
    required Map<String, dynamic>? workInfo,
    required String fallbackCircle,
    required Future<Map<String, dynamic>?> Function(String id)
        fetchWorkInfo,
  }) async {
    if (workInfo == null) return fallbackCircle;

    final translationInfo =
        workInfo['translation_info'] as Map<String, dynamic>?;
    // 原版作品直接用当前 circle
    if (translationInfo?['is_original'] == true) {
      return fallbackCircle;
    }

    // 汉化版：从其他语言版本中找原版，取原版 circle
    try {
      final editions =
          workInfo['other_language_editions_in_db'] as List? ?? const [];
      for (final edition in editions) {
        final e = edition as Map<String, dynamic>;
        if (e['is_original'] == true && e['id'] != null) {
          final originalInfo = await fetchWorkInfo(e['id'].toString());
          final originalCircle =
              originalInfo?['circle']?['name']?.toString();
          if (originalCircle != null && originalCircle.isNotEmpty) {
            return originalCircle;
          }
        }
      }
    } catch (e) {
      Log.error('resolve original circle failed\n' 'error: $e');
    }

    return fallbackCircle;
  }

  /// [sourceDir] 下载的作品目录（`<voiceWorkPath>/<sourceId>`）
  /// [targetRoot] Navidrome 媒体库根目录
  /// [coverBytes] 封面字节，非空时保存为 `cover.jpg`
  /// [artist] 标签 artist 字段（CV 声优名）
  /// [albumArtist] 标签 albumartist 字段（CV 声优名）
  /// [releaseDate] 发行日期（如 2026-06-18），年份写入标签
  /// [genres] 流派标签列表
  ///
  /// 字幕处理：同名 .lrc 直接使用（优先）；同名 .vtt 自动转换为 LRC，
  /// 内嵌为音频歌词标签并额外生成 `<音频名>.lrc` 侧车文件。
  static Future<OrganizeResult> organize({
    required String sourceDir,
    required String targetRoot,
    required String circleName,
    required String sourceId,
    required String cvNames,
    required String title,
    Uint8List? coverBytes,
    String artist = '',
    String albumArtist = '',
    String releaseDate = '',
    List<String> genres = const [],
  }) async {
    final source = Directory(sourceDir);
    if (!await source.exists()) {
      throw StateError('源目录不存在: $sourceDir');
    }

    // 目标目录：<targetRoot>/<circle>/<sourceId> - <cv> - <title>/<sourceId>
    // 目录名过长时智能截断（保留 sourceId，按字符/字节双上限，尾部加 …）
    var circleDirName = getLegalWindowsName(smartTruncate(
        circleName.isEmpty ? cvNames : circleName,
        maxChars: kMaxCircleDirChars,
        maxUtf8Bytes: kMaxCircleDirUtf8Bytes));
    if (circleDirName.isEmpty) circleDirName = sourceId;
    // 空字段省略，降级模式下 cv/title 缺失时不会出现 "RJ -  - " 残留分隔符
    var albumDirName = getLegalWindowsName(smartTruncate(
        [sourceId, cvNames, title].where((s) => s.isNotEmpty).join(' - '),
        maxChars: kMaxAlbumDirChars,
        maxUtf8Bytes: kMaxAlbumDirUtf8Bytes));
    // 极端情况兜底（截断后为空时）至少保留 sourceId
    if (albumDirName.isEmpty) albumDirName = sourceId;
    final targetDir = p.join(targetRoot, circleDirName, albumDirName, sourceId);

    int copied = 0;
    int skipped = 0;
    int tagWriteFailures = 0;

    // 封面：复用已获取的封面字节，保存为 Navidrome 识别的 cover.jpg
    if (coverBytes != null) {
      final coverFile = File(p.join(targetDir, 'cover.jpg'));
      if (await coverFile.exists() &&
          await coverFile.length() == coverBytes.length) {
        skipped++;
      } else {
        await coverFile.create(recursive: true);
        await coverFile.writeAsBytes(coverBytes);
        copied++;
        Log.info('organize cover: ${coverFile.path}');
      }
    }

    // 收集源目录下所有文件（跳过隐藏文件和下载器生成的 *_cover.jpg）
    final files = <File>[];
    await _collectFiles(source, files);

    // 建立歌词映射：音频引用名 → 歌词文本。
    // 字幕文件命名可能带音频扩展名（"xxx.mp3.vtt" → key "xxx.mp3"）
    // 或不带（"xxx.vtt" → key "xxx"），音频查找时两种 key 都试。
    // 优先级：同名 .lrc > 同名 .vtt 转换结果（lrc 是人工/官方字幕，优先）。
    final lrcMap = <String, String>{};
    final vttMap = <String, String>{};

    Future<void> readSubtitle(File file, String suffix) async {
      final name = p.basename(file.path);
      if (!name.toLowerCase().endsWith(suffix)) return;
      final key = name.substring(0, name.length - suffix.length);
      try {
        final content = await file.readAsString();
        if (suffix == '.lrc') {
          lrcMap[key] = content;
        } else {
          final converted = vttToLrc(content);
          if (converted != null) {
            vttMap[key] = converted;
          }
        }
      } catch (e) {
        Log.warning('read subtitle failed: ${file.path}\n' 'error: $e');
      }
    }

    for (final file in files) {
      await readSubtitle(file, '.lrc');
    }
    for (final file in files) {
      await readSubtitle(file, '.vtt');
    }

    /// 音频文件的歌词：完整名或去扩展名两种 key，lrc 优先于 vtt
    String? lyricsFor(String audioBasename) {
      final base = p.basenameWithoutExtension(audioBasename);
      return lrcMap[audioBasename] ??
          lrcMap[base] ??
          vttMap[audioBasename] ??
          vttMap[base];
    }

    // 扁平化复制到目标目录
    for (final file in files) {
      final targetFile = File(p.join(targetDir, p.basename(file.path)));
      if (await targetFile.exists() &&
          await targetFile.length() == await file.length()) {
        skipped++;
      } else {
        await targetFile.create(recursive: true);
        await file.copy(targetFile.path);
        copied++;
      }

      // 音频文件写标签（title/artist/album/albumartist/track/内嵌歌词/内嵌封面/年份/流派）
      if (AudioTagWriter.isAudioFile(targetFile.path)) {
        final audioName = p.basename(file.path);
        final base = p.basenameWithoutExtension(audioName);
        final lyrics = lyricsFor(audioName);

        // VTT 转换出的歌词额外生成为 .lrc 侧车文件
        // （供 mp3tag 等其他工具使用；已有真实 .lrc 时跳过，避免覆盖）
        final hasRealLrc =
            lrcMap.containsKey(audioName) || lrcMap.containsKey(base);
        if (lyrics != null &&
            !hasRealLrc &&
            (vttMap.containsKey(audioName) || vttMap.containsKey(base))) {
          final lrcFile = File(p.join(targetDir, '$audioName.lrc'));
          final existing = await lrcFile.exists()
              ? await lrcFile.readAsString()
              : null;
          if (existing == lyrics) {
            skipped++;
          } else {
            await lrcFile.writeAsString(lyrics);
            copied++;
            Log.info('organize lrc from vtt: ${lrcFile.path}');
          }
        }

        final track = _parseTrackNumber(audioName);
        final tagOk = await AudioTagWriter.writeTags(
          targetFile.path,
          title: base,
          artist: artist,
          album: title,
          albumArtist: albumArtist,
          track: track,
          // 内嵌歌词：同名 LRC 或 VTT 转换结果（wav 不支持则自动跳过）
          lyrics: lyrics,
          // 专辑封面嵌入每首歌（wav 不支持则自动跳过）
          coverBytes: coverBytes,
          // 发行年份（releaseDate 取前 4 位）
          year: releaseDate.length >= 4 ? releaseDate.substring(0, 4) : null,
          // 流派（前 3 个，防止字段过长）
          genre: genres.take(3).join('; '),
        );
        if (!tagOk) tagWriteFailures++;
      }
    }

    Log.info('organize completed: copied $copied, skipped $skipped, '
        'tagWriteFailures $tagWriteFailures\n'
        'targetDir: $targetDir');
    return OrganizeResult(
      copied: copied,
      skipped: skipped,
      tagWriteFailures: tagWriteFailures,
    );
  }

  /// 从文件名解析 track number（如 "01 xxx.wav" → "1"），无法解析返回 null
  static String? _parseTrackNumber(String fileName) {
    final match = RegExp(r'^(\d+)').firstMatch(fileName);
    if (match == null) return null;
    return int.parse(match.group(1)!).toString();
  }

  static Future<void> _collectFiles(Directory dir, List<File> result) async {
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        await _collectFiles(entity, result);
      } else if (entity is File) {
        final name = p.basename(entity.path);
        // 跳过隐藏文件（如 .DS_Store）和下载器生成的封面
        if (name.startsWith('.') || name.endsWith('_cover.jpg')) {
          continue;
        }
        result.add(entity);
      }
    }
  }
}
