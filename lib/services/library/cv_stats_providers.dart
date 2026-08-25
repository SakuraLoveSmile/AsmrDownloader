import 'dart:io';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/cache/cache_library_providers.dart';
import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// 单个 CV（声优/艺术家）的聚合统计。
class CvStat {
  final String name;
  final int albumCount;
  final int trackCount;

  const CvStat({
    required this.name,
    required this.albumCount,
    required this.trackCount,
  });
}

/// 全部 CV 的统计：专辑数（含该 CV 的作品数）与歌曲数（audio 节点总数）。
///
/// 数据源为媒体库已扫描到的作品（与 Navidrome 实际可见的库一致），
/// 每个作品按 CV 名单分别计入各 CV；作品内重复的 CV 名只计一次；
/// 无 CV 名的作品不计入。
final cvStatsProvider = FutureProvider<List<CvStat>>((ref) async {
  final library = await ref.watch(cachedLibraryProvider.future);
  final cache = ref.watch(cacheServiceProvider);
  final trackCounts = await cache.getAudioTrackCounts();

  final statByName = <String, CvStat>{};
  for (final entry in library.entries) {
    // 同作品内去重，避免一个作品列了两次同一 CV 时重复计数。
    final cvNames = entry.cvNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    for (final name in cvNames) {
      final current =
          statByName[name] ?? CvStat(name: name, albumCount: 0, trackCount: 0);
      statByName[name] = CvStat(
        name: name,
        albumCount: current.albumCount + 1,
        trackCount: current.trackCount + (trackCounts[entry.sourceId] ?? 0),
      );
    }
  }

  final list = statByName.values.toList();
  list.sort((a, b) {
    // 专辑数降序 → 歌曲数降序 → 名称小写比较。
    if (a.albumCount != b.albumCount) {
      return b.albumCount.compareTo(a.albumCount);
    }
    if (a.trackCount != b.trackCount) {
      return b.trackCount.compareTo(a.trackCount);
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return list;
});

/// 头像目录索引：扫描 `cvAvatarPath`，收集 Navidrome 支持的图片扩展名
/// （jpg/jpeg/png/webp/gif），key 为去扩展名的文件名。
///
/// 同时写入「精确名」与「全小写」两个键：查询时精确名优先，
/// 找不到再退回小写 fallback，行为与 Navidrome 按艺术家名匹配文件名一致。
/// 目录为空或不存在时返回空 map。
final cvAvatarIndexProvider = FutureProvider<Map<String, String>>((ref) async {
  final dirPath = ref.watch(cvAvatarPathProvider).trim();
  if (dirPath.isEmpty) return const {};
  final dir = Directory(dirPath);
  if (!await dir.exists()) return const {};

  const exts = {'jpg', 'jpeg', 'png', 'webp', 'gif'};
  final index = <String, String>{};
  await for (final entity in dir.list()) {
    if (entity is! File) continue;
    final ext = p.extension(entity.path).toLowerCase();
    if (ext.isEmpty || !exts.contains(ext.substring(1))) continue;
    final baseName = p.basenameWithoutExtension(entity.path);
    if (baseName.isEmpty) continue;
    // 精确名始终写入；小写 fallback 仅在尚无该精确名时写入，保证精确优先。
    index[baseName] = entity.path;
    final lower = baseName.toLowerCase();
    index.putIfAbsent(lower, () => entity.path);
  }
  return index;
});

/// 在头像索引中按 CV 名查找头像真实路径：
/// 先 sanitize 文件系统非法字符，再精确匹配；无精确匹配时退回小写 fallback。
String? findCvAvatarPath(Map<String, String> index, String cvName) {
  final key = sanitizeCvName(cvName);
  if (key.isEmpty) return null;
  final exact = index[key];
  if (exact != null) return exact;
  return index[key.toLowerCase()];
}

/// 把文件名中的文件系统非法字符（`\ / : * ? " < > |` 及控制字符）替换为下划线。
/// 索引写入与查询共用，保证「CV 名 → 头像文件名」的映射一致。
String sanitizeCvName(String name) {
  return name
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '_')
      .trim();
}

/// 把 [sourceFile] 复制为头像目录下的 `<sanitized-name><原扩展名>`，
/// 覆盖同名旧文件，随后使索引失效以刷新。
Future<void> setCvAvatar(
  Ref ref,
  String dir,
  String cvName,
  String sourceFile,
) async {
  final dirPath = dir.trim();
  if (dirPath.isEmpty) return;
  final srcFile = File(sourceFile);
  if (!await srcFile.exists()) return;

  final sanitized = sanitizeCvName(cvName);
  if (sanitized.isEmpty) return;
  final ext = p.extension(sourceFile).toLowerCase();
  final destPath = p.join(dirPath, '$sanitized$ext');

  try {
    await srcFile.copy(destPath);
    Log.info('cv avatar set: $cvName -> $destPath');
  } catch (e) {
    Log.warning('set cv avatar failed: $cvName\nerror: $e');
    return;
  }
  ref.invalidate(cvAvatarIndexProvider);
}

/// 删除该 CV 对应的头像文件（用索引查到的实际路径），随后使索引失效。
Future<void> clearCvAvatar(
  Ref ref,
  String dir,
  String cvName,
) async {
  final dirPath = dir.trim();
  if (dirPath.isEmpty) return;

  final index = await ref.read(cvAvatarIndexProvider.future);
  final path = findCvAvatarPath(index, cvName);
  if (path == null) return;

  try {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
      Log.info('cv avatar cleared: $cvName -> $path');
    }
  } catch (e) {
    Log.warning('clear cv avatar failed: $cvName\nerror: $e');
    return;
  }
  ref.invalidate(cvAvatarIndexProvider);
}

/// 从文件选择器结果中取出首个图片路径（供 UI 调用）。
String? firstPickedImagePath(FilePickerResult? result) {
  return result?.files.firstOrNull?.path;
}

/// [setCvAvatar] 的 provider 包装：UI 与测试都通过 `ref.read(...)` 调用，
/// 由 Riverpod 提供 `Ref`，避免在 widget 外手动构造 WidgetRef。
typedef SetCvAvatarArgs = ({String dir, String cvName, String sourceFile});

final setCvAvatarProvider =
    FutureProvider.family<void, SetCvAvatarArgs>((ref, args) {
  return setCvAvatar(ref, args.dir, args.cvName, args.sourceFile);
});

/// [clearCvAvatar] 的 provider 包装。
typedef ClearCvAvatarArgs = ({String dir, String cvName});

final clearCvAvatarProvider =
    FutureProvider.family<void, ClearCvAvatarArgs>((ref, args) {
  return clearCvAvatar(ref, args.dir, args.cvName);
});
