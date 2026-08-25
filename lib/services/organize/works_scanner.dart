import 'dart:io';

import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:path/path.dart' as p;

/// 扫描命中：同一 sourceId 出现多处时用于取舍的中间记录。
///
/// [entryPath] 为实际命中的目录绝对路径，用于判断两次命中是否父子嵌套。
typedef _ScanHit = ({
  String sourceId,
  String dlPath,
  String dirName,
  int depth,
  String entryPath,
});

/// 扫描下载根目录，识别带 RJ/VJ/BJ 号的作品目录（不依赖注册表）。
///
/// 返回合成 WorkEntry（title/cvNames 为空，整理时按目录名降级解析/在线拉取）。
/// [excludeRoot] 整理目标根目录，位于其下的目录不作为源扫描（防止把整理产物再整理）。
///
/// 同一 sourceId 多处出现时的取舍规则（见 [_preferNewHit]）：
/// - 父子目录同时命中（外层为 "RJ号 - CV - 标题" 包装目录、内层才是真正的
///   RJ 作品目录）时优先保留更深的内层目录；
/// - 两个目录互不包含时保留最浅路径。
///
/// 生成的 WorkEntry 针对扁平作品目录（"RJ号 - CV - 标题/" 直接存放音频）
/// 设置 [WorkEntry.sourceDirOverride] 指向真实目录；标准结构
/// （"CV-标题/RJ123456/" 或内层 RJ 目录）按 {dlPath}/{dirName}/{sourceId}
/// 重建，不设置 override。
/// 跳过隐藏目录。
Future<List<WorkEntry>> scanDownloadRoot({
  required String dlRoot,
  String? excludeRoot,
  int maxDepth = 4,
}) async {
  if (dlRoot.isEmpty) return const [];

  final found = <String, _ScanHit>{};

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
          if (prev == null || _preferNewHit(prev, entity.path, depth)) {
            // 目录结构 <dlRoot>/<dirName>/<sourceId>（dirName 可为空）
            final parentPath = p.dirname(entity.path);
            final isFlat = p.equals(parentPath, dlRoot);
            found[sourceId] = (
              sourceId: sourceId,
              dlPath: isFlat ? dlRoot : p.dirname(parentPath),
              // RJ 目录直接平铺在下载根下时 dirName 为空（p.join 自动跳过空段）
              dirName: isFlat ? '' : p.basename(parentPath),
              depth: depth,
              entryPath: entity.path,
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
  return found.values.map((f) {
    // 命中目录名与 sourceId 完全一致（如 "CV-标题/RJ123456/"）：
    // 继续用 {dlPath}/{dirName}/{sourceId} 重建作品目录，不设置 override。
    // 扁平后缀目录（如 "RJ123456 - CV - 标题/"）无法按标准结构重建：
    // 直接指向命中目录本身，dirName 保留完整三段式名称供 parseDirName 解析。
    final isStandard = p.basename(f.entryPath).toUpperCase() == f.sourceId;
    return WorkEntry(
      sourceId: f.sourceId,
      dlPath: isStandard ? f.dlPath : p.dirname(f.entryPath),
      dirName: isStandard ? f.dirName : p.basename(f.entryPath),
      title: '',
      cvNames: '',
      sourceDirOverride: isStandard ? '' : f.entryPath,
    );
  }).toList();
}

/// 同一 sourceId 两次命中时，新命中是否取代旧命中：
/// - 新目录位于旧目录内（父子命中）→ 取代，取更深的内层目录，得到
///   `dirName = "RJ号 - CV - 标题"`、`sourceDir = <circle>/RJ号 - CV - 标题/RJ号`；
/// - 旧目录位于新目录内 → 不取代，保留内层目录；
/// - 两个目录互不包含（同一作品的独立副本）→ 沿用最浅路径规则。
bool _preferNewHit(_ScanHit prev, String newPath, int depth) {
  if (p.isWithin(prev.entryPath, newPath)) return true;
  if (p.isWithin(newPath, prev.entryPath)) return false;
  return depth < prev.depth;
}
