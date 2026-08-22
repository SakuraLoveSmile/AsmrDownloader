import 'dart:io';

import 'package:asmr_downloader/utils/log.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:path/path.dart' as p;

/// 媒体库轻量扫描命中。
class MediaLibraryScanHit {
  const MediaLibraryScanHit({
    required this.sourceId,
    required this.rootPath,
    required this.matchedPath,
    required this.depth,
  });

  final String sourceId;
  final String rootPath;
  final String matchedPath;
  final int depth;
}

/// 只扫描目录名中的 RJ/VJ/BJ 号，不读取目录内的文件。
///
/// 常见目录结构是 `<root>/<社团-标题>/RJxxxxxxxx`，因此默认扫描 4 层已经
/// 足够覆盖下载目录和 NAS 整理目录。相同根目录下同一个作品出现多次时，
/// 只保留最浅路径；扫描结果只用于作品存在性，不代表音频文件完整。
Future<List<MediaLibraryScanHit>> scanMediaLibraryRoot({
  required String rootPath,
  int maxDepth = 4,
}) async {
  final normalizedRoot = _normalizePath(rootPath);
  if (normalizedRoot.isEmpty) return const [];

  final root = Directory(normalizedRoot);
  if (!await root.exists()) return const [];

  final found = <String, MediaLibraryScanHit>{};

  Future<void> walk(Directory dir, int depth) async {
    if (depth > maxDepth) return;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final entityPath = _normalizePath(entity.path);
        final name = p.basename(entityPath);
        if (name.startsWith('.')) continue;

        final sourceId = matchSourceIdFromDirName(name);
        if (sourceId != null) {
          final hit = MediaLibraryScanHit(
            sourceId: sourceId,
            rootPath: normalizedRoot,
            matchedPath: entityPath,
            depth: depth + 1,
          );
          final previous = found[sourceId];
          if (previous == null || hit.depth < previous.depth) {
            found[sourceId] = hit;
          }
          // RJ 目录本身已经是作品边界；不继续进入其子目录，避免把作品
          // 内部的文件夹当成媒体库结构，也让 NAS 扫描保持轻量。
          continue;
        }

        // 只枚举目录项，不读取任何文件内容。
        await walk(entity, depth + 1);
      }
    } catch (e) {
      // 单个无权限子目录不应阻断整个 NAS 根目录的扫描。
      Log.warning('scan media library dir failed: ${dir.path}\nerror: $e');
    }
  }

  // 配置根目录本身也可能就是 RJxxxxxxxx。
  final rootSourceId = matchSourceIdFromDirName(p.basename(normalizedRoot));
  if (rootSourceId != null) {
    found[rootSourceId] = MediaLibraryScanHit(
      sourceId: rootSourceId,
      rootPath: normalizedRoot,
      matchedPath: normalizedRoot,
      depth: 0,
    );
  }

  await walk(root, 0);
  final result = found.values.toList()
    ..sort((a, b) => a.sourceId.compareTo(b.sourceId));
  return result;
}

String _normalizePath(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? '' : p.normalize(trimmed);
}
