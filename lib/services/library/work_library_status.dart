import 'dart:io';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/library/media_library_service.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// 当前搜索作品的入库状态（搜索结果页徽章展示用）。
class WorkLibraryStatus {
  const WorkLibraryStatus({
    required this.localPaths,
    required this.externalLocations,
  });

  /// 本机已有的副本路径（注册表记录的下载目录 / 当前命名目录 /
  /// 下载根目录内的扫描记录）。
  final List<String> localPaths;

  /// 下载根目录之外（NAS/整理目录等）的媒体库扫描记录；
  /// 这类副本会让下载前的重复检测跳过下载。
  final List<MediaLibraryLocationItem> externalLocations;

  bool get inLibrary => localPaths.isNotEmpty || externalLocations.isNotEmpty;
}

/// 搜索作品的入库状态：本机目录 + 媒体库扫描记录。
///
/// 只读已有扫描结果（不触发重扫，避免每次搜索都遍历 NAS）；
/// 下载前的重复检测（findExistingOutsideRoot）仍会实时重扫兜底。
/// 数据变化后由下载完成/媒体库扫描/删除作品等入口 invalidate 刷新。
final workLibraryStatusProvider =
    FutureProvider<WorkLibraryStatus?>((ref) async {
  final sourceId = ref.watch(sourceIdProvider);
  if (sourceId == null) return null;

  final localPaths = <String>[];

  // 注册表（下载完成写入）且目录仍存在的记录
  final entry = await ref.watch(worksIndexProvider).get(sourceId);
  if (entry != null && Directory(entry.sourceDir).existsSync()) {
    localPaths.add(entry.sourceDir);
  }

  // 当前命名规则下的作品目录（voiceWorkPath 随标题解析自动重算，
  // 断点续传的未完成目录也在覆盖范围内）
  final currentDir = p.join(ref.watch(voiceWorkPathProvider), sourceId);
  if (Directory(currentDir).existsSync() &&
      !_containsPath(localPaths, currentDir)) {
    localPaths.add(currentDir);
  }

  // 媒体库扫描记录：位于下载根目录内算本机副本，其余算外部副本
  final downloadPath = ref.watch(downloadPathProvider).trim();
  final locations = await ref
      .watch(mediaLibraryServiceProvider)
      .listLocations(roots: ref.watch(mediaLibraryRootsProvider));
  final external = <MediaLibraryLocationItem>[];
  for (final location in locations) {
    if (location.sourceId != sourceId) continue;
    if (_within(location.matchedPath, downloadPath)) {
      if (!_containsPath(localPaths, location.matchedPath)) {
        localPaths.add(location.matchedPath);
      }
    } else {
      external.add(location);
    }
  }

  return WorkLibraryStatus(
    localPaths: List.unmodifiable(localPaths),
    externalLocations: List.unmodifiable(external),
  );
});

bool _containsPath(List<String> paths, String path) {
  final normalized = p.normalize(path);
  return paths.any((existing) => p.equals(p.normalize(existing), normalized));
}

bool _within(String path, String root) {
  final normalizedRoot = p.normalize(root.trim());
  if (normalizedRoot.isEmpty || normalizedRoot == '.') return false;
  final normalizedPath = p.normalize(path);
  return p.equals(normalizedPath, normalizedRoot) ||
      p.isWithin(normalizedRoot, normalizedPath);
}
