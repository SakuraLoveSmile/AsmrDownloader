import 'dart:io';
import 'dart:typed_data';

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
  /// [sourceDir] 下载的作品目录（`<voiceWorkPath>/<sourceId>`）
  /// [targetRoot] Navidrome 媒体库根目录
  /// [coverBytes] 封面字节，非空时保存为 `cover.jpg`
  static Future<OrganizeResult> organize({
    required String sourceDir,
    required String targetRoot,
    required String circleName,
    required String sourceId,
    required String cvNames,
    required String title,
    Uint8List? coverBytes,
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
    }

    Log.info('organize completed: copied $copied, skipped $skipped\n'
        'targetDir: $targetDir');
    return OrganizeResult(copied: copied, skipped: skipped);
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
