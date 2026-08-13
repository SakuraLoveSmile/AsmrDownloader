import 'dart:io';
import 'dart:typed_data';

import 'package:asmr_downloader/services/organize/audio_tag_writer.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:path/path.dart' as p;

class OrganizeResult {
  final int copied;
  final int skipped;

  const OrganizeResult({required this.copied, required this.skipped});
}

/// 将下载的作品整理成 Navidrome 媒体库结构：
/// `<targetRoot>/<circleName>/<sourceId> - <cvNames> - <title>/<sourceId>/`
/// 音轨/字幕/歌词文件扁平化复制，保留原名；封面保存为 cover.jpg（Navidrome 自动识别）。
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
  /// [artist] 标签 artist 字段（社团名）
  /// [albumArtist] 标签 albumartist 字段（CV 名）
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
  }) async {
    final source = Directory(sourceDir);
    if (!await source.exists()) {
      throw StateError('源目录不存在: $sourceDir');
    }

    // 目标目录：<targetRoot>/<circle>/<sourceId> - <cv> - <title>/<sourceId>
    final circleDirName =
        getLegalWindowsName(circleName.isEmpty ? cvNames : circleName);
    final albumDirName =
        getLegalWindowsName('$sourceId - $cvNames - $title');
    final targetDir = p.join(targetRoot, circleDirName, albumDirName, sourceId);

    int copied = 0;
    int skipped = 0;

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

      // 音频文件写标签（title/artist/album/albumartist/track）
      if (AudioTagWriter.isAudioFile(targetFile.path)) {
        final track = _parseTrackNumber(p.basename(file.path));
        await AudioTagWriter.writeTags(
          targetFile.path,
          title: p.basenameWithoutExtension(file.path),
          artist: artist,
          album: title,
          albumArtist: albumArtist,
          track: track,
        );
      }
    }

    Log.info('organize completed: copied $copied, skipped $skipped\n'
        'targetDir: $targetDir');
    return OrganizeResult(copied: copied, skipped: skipped);
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
