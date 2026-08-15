import 'dart:io';

import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:path/path.dart' as p;

/// 扫描下载根目录，识别带 RJ/VJ/BJ 号的作品目录（不依赖注册表）。
///
/// 返回合成 WorkEntry（title/cvNames 为空，整理时按目录名降级解析/在线拉取）。
/// [excludeRoot] 整理目标根目录，位于其下的目录不作为源扫描（防止把整理产物再整理）。
/// 同一 sourceId 多处出现时取最浅路径；跳过隐藏目录。
Future<List<WorkEntry>> scanDownloadRoot({
  required String dlRoot,
  String? excludeRoot,
  int maxDepth = 4,
}) async {
  if (dlRoot.isEmpty) return const [];

  final found = <String,
      ({String sourceId, String dlPath, String dirName, int depth})>{};

  Future<void> walk(Directory dir, int depth) async {
    if (depth > maxDepth) return;
    try {
      await for (final entity in dir.list()) {
        if (entity is! Directory) continue;
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        if (excludeRoot != null && p.equals(entity.path, excludeRoot)) {
          continue;
        }
        final sourceId = matchSourceIdFromDirName(name);
        if (sourceId != null) {
          final prev = found[sourceId];
          if (prev == null || depth < prev.depth) {
            // 目录结构 <dlRoot>/<dirName>/<sourceId>（dirName 可为空）
            final parentPath = p.dirname(entity.path);
            final isFlat = p.equals(parentPath, dlRoot);
            found[sourceId] = (
              sourceId: sourceId,
              dlPath: isFlat ? dlRoot : p.dirname(parentPath),
              // RJ 目录直接平铺在下载根下时 dirName 为空（p.join 自动跳过空段）
              dirName: isFlat ? '' : p.basename(parentPath),
              depth: depth,
            );
          }
        }
        await walk(entity, depth + 1);
      }
    } catch (e) {
      Log.warning('scan download dir failed: ${dir.path}\n' 'error: $e');
    }
  }

  await walk(Directory(dlRoot), 1);
  return found.values
      .map((f) => WorkEntry(
            sourceId: f.sourceId,
            dlPath: f.dlPath,
            dirName: f.dirName,
            title: '',
            cvNames: '',
          ))
      .toList();
}
