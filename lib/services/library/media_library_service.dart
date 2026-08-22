import 'dart:io';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/library/library_database.dart';
import 'package:asmr_downloader/services/library/library_database_providers.dart';
import 'package:asmr_downloader/services/library/media_library_scanner.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// 媒体库数据库中的一个已知位置。
class MediaLibraryLocationItem {
  const MediaLibraryLocationItem({
    required this.sourceId,
    required this.rootPath,
    required this.matchedPath,
    required this.depth,
    required this.scannedAt,
  });

  final String sourceId;
  final String rootPath;
  final String matchedPath;
  final int depth;
  final DateTime scannedAt;
}

class MediaLibraryScanSummary {
  const MediaLibraryScanSummary({
    required this.roots,
    required this.scannedRoots,
    required this.workCount,
    required this.unavailableRoots,
  });

  final List<String> roots;
  final int scannedRoots;
  final int workCount;
  final List<String> unavailableRoots;
}

/// 媒体库服务：保存扫描结果，并把扫描到的 sourceId 与缓存数据库关联。
///
/// 扫描只落库作品目录位置，不统计文件数量、大小、音轨或字幕状态。
class MediaLibraryService {
  MediaLibraryService(this.ref, this.database);

  final Ref ref;
  final LibraryDatabase database;

  Future<MediaLibraryScanSummary> scanConfiguredRoots({
    List<String>? roots,
    int maxDepth = 4,
  }) async {
    final configured = _normalizeRoots(
      roots ?? ref.read(mediaLibraryRootsProvider),
    );
    final unavailable = <String>[];
    var scannedRoots = 0;

    for (final root in configured) {
      final directory = Directory(root);
      if (!await directory.exists()) {
        unavailable.add(root);
        await _markRoot(root, error: '目录不存在或当前未挂载');
        continue;
      }

      try {
        final hits = await scanMediaLibraryRoot(
          rootPath: root,
          maxDepth: maxDepth,
        );
        await database.transaction(() async {
          // 只有一次完整扫描成功后才替换旧结果；NAS 暂时不可用时，
          // 上次看到的 RJ 号仍然保留，避免用户重复下载。
          await (database.delete(database.mediaLibraryLocations)
                ..where((t) => t.rootPath.equals(root)))
              .go();
          for (final hit in hits) {
            await database
                .into(database.mediaLibraryLocations)
                .insertOnConflictUpdate(
                  MediaLibraryLocationsCompanion.insert(
                    sourceId: hit.sourceId,
                    rootPath: hit.rootPath,
                    matchedPath: hit.matchedPath,
                    depth: Value(hit.depth),
                    scannedAt: Value(DateTime.now()),
                  ),
                );
          }
          await database
              .into(database.mediaLibraryRoots)
              .insertOnConflictUpdate(
                MediaLibraryRootsCompanion.insert(
                  rootPath: root,
                  lastScannedAt: Value(DateTime.now()),
                  lastError: const Value(null),
                ),
              );
        });
        scannedRoots++;
      } catch (e) {
        unavailable.add(root);
        Log.warning('scan media library root failed: $root\nerror: $e');
        await _markRoot(root, error: e.toString());
      }
    }

    return MediaLibraryScanSummary(
      roots: configured,
      scannedRoots: scannedRoots,
      workCount: (await listLocations(roots: configured))
          .map((item) => item.sourceId)
          .toSet()
          .length,
      unavailableRoots: unavailable,
    );
  }

  Future<List<MediaLibraryLocationItem>> listLocations({
    List<String>? roots,
  }) async {
    final allowedRoots = roots == null ? null : _normalizeRoots(roots);
    final rows = await (database.select(database.mediaLibraryLocations)
          ..orderBy([
            (t) => OrderingTerm.asc(t.sourceId),
            (t) => OrderingTerm.asc(t.rootPath),
          ]))
        .get();
    return rows
        .where((row) =>
            allowedRoots == null || allowedRoots.contains(row.rootPath))
        .map(
          (row) => MediaLibraryLocationItem(
            sourceId: row.sourceId,
            rootPath: row.rootPath,
            matchedPath: row.matchedPath,
            depth: row.depth,
            scannedAt: row.scannedAt,
          ),
        )
        .toList();
  }

  Future<bool> containsSourceId(String sourceId) async {
    final rows = await (database.select(database.mediaLibraryLocations)
          ..where((t) => t.sourceId.equals(sourceId)))
        .get();
    return rows.isNotEmpty;
  }

  /// 扫描后查找本机临时下载根目录之外的已知副本。
  ///
  /// 本机下载目录可能存在未完成的断点目录，不能仅凭 RJ 目录存在就阻止
  /// 恢复下载；NAS/其它扫描根目录则可以作为已完成内容的持久化依据。
  Future<MediaLibraryLocationItem?> findExistingOutsideRoot({
    required String sourceId,
    String? excludedRoot,
  }) async {
    await scanConfiguredRoots();
    final excluded = excludedRoot == null || excludedRoot.trim().isEmpty
        ? null
        : _normalizeRoot(excludedRoot);
    final locations = await listLocations(
      roots: ref.read(mediaLibraryRootsProvider),
    );
    for (final location in locations) {
      if (location.sourceId != sourceId) continue;
      if (excluded == null || !_samePath(location.rootPath, excluded)) {
        return location;
      }
    }
    return null;
  }

  Future<List<MediaLibraryRootState>> listRootStates() async {
    final rows = await (database.select(database.mediaLibraryRoots)
          ..orderBy([(t) => OrderingTerm.asc(t.rootPath)]))
        .get();
    return rows
        .map(
          (row) => MediaLibraryRootState(
            rootPath: row.rootPath,
            lastScannedAt: row.lastScannedAt,
            lastError: row.lastError,
          ),
        )
        .toList();
  }

  Future<void> removeRoot(String rootPath) async {
    final normalized = _normalizeRoot(rootPath);
    if (normalized.isEmpty) return;
    await database.transaction(() async {
      await (database.delete(database.mediaLibraryLocations)
            ..where((t) => t.rootPath.equals(normalized)))
          .go();
      await (database.delete(database.mediaLibraryRoots)
            ..where((t) => t.rootPath.equals(normalized)))
          .go();
    });
  }

  Future<void> _markRoot(String root, {required String error}) async {
    await database.into(database.mediaLibraryRoots).insertOnConflictUpdate(
          MediaLibraryRootsCompanion.insert(
            rootPath: root,
            lastError: Value(error),
          ),
        );
  }

  static List<String> _normalizeRoots(Iterable<String> roots) {
    final result = <String>[];
    final seen = <String>{};
    for (final root in roots) {
      final normalized = _normalizeRoot(root);
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      result.add(normalized);
    }
    return result;
  }

  static String _normalizeRoot(String root) {
    final trimmed = root.trim();
    return trimmed.isEmpty ? '' : p.normalize(trimmed);
  }

  static bool _samePath(String left, String right) =>
      p.equals(_normalizeRoot(left), _normalizeRoot(right));
}

class MediaLibraryRootState {
  const MediaLibraryRootState({
    required this.rootPath,
    required this.lastScannedAt,
    required this.lastError,
  });

  final String rootPath;
  final DateTime? lastScannedAt;
  final String? lastError;
}

final mediaLibraryServiceProvider = Provider<MediaLibraryService>((ref) {
  return MediaLibraryService(ref, ref.watch(libraryDatabaseProvider));
});
