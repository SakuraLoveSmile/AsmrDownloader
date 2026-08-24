import 'dart:convert';
import 'dart:io';

import 'package:asmr_downloader/services/cache/cache_database.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:drift/drift.dart';

/// 本地缓存读写服务：workInfo / tracks 原始 JSON + 封面 BLOB。
/// 所有查询按 sourceId 主键读写；导入导出通过复制 .db 文件完成。
class CacheService {
  CacheService(this._db);

  /// 非 final：导入新数据库文件后整体替换连接
  CacheDatabase _db;

  CacheDatabase get database => _db;

  /// 数据库文件路径
  String get dbPath => _db.dbFilePath;

  // ---------- workInfo ----------

  Future<Map<String, dynamic>?> getWorkInfo(String sourceId) async {
    try {
      final entry = await (_db.select(_db.workInfoEntries)
            ..where((t) => t.sourceId.equals(sourceId)))
          .getSingleOrNull();
      if (entry == null) return null;
      final decoded = jsonDecode(entry.workInfoJson);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      Log.warning('read workInfo cache failed: $sourceId\n' 'error: $e');
      return null;
    }
  }

  /// 列出全部 workInfo，按最近缓存时间倒序。
  Future<List<WorkInfoEntry>> listWorkInfoEntries() async {
    try {
      final query = _db.select(_db.workInfoEntries)
        ..orderBy([(t) => OrderingTerm.desc(t.cachedAt)]);
      return await query.get();
    } catch (e) {
      Log.warning('list workInfo cache failed\n' 'error: $e');
      return [];
    }
  }

  /// 只读取 tracks 主键，避免批量加载原始 JSON。
  Future<Set<String>> listTracksSourceIds() async {
    try {
      final query = _db.selectOnly(_db.tracksEntries)
        ..addColumns([_db.tracksEntries.sourceId]);
      final rows = await query.get();
      return rows
          .map((row) => row.read(_db.tracksEntries.sourceId))
          .whereType<String>()
          .toSet();
    } catch (e) {
      Log.warning('list tracks cache ids failed\n' 'error: $e');
      return {};
    }
  }

  /// 只读取封面主键，避免批量加载 BLOB。
  Future<Set<String>> listCoverSourceIds() async {
    try {
      final query = _db.selectOnly(_db.coverEntries)
        ..addColumns([_db.coverEntries.sourceId]);
      final rows = await query.get();
      return rows
          .map((row) => row.read(_db.coverEntries.sourceId))
          .whereType<String>()
          .toSet();
    } catch (e) {
      Log.warning('list cover cache ids failed\n' 'error: $e');
      return {};
    }
  }

  Future<void> saveWorkInfo(String sourceId, Map<String, dynamic> data) async {
    try {
      await _db.into(_db.workInfoEntries).insertOnConflictUpdate(
            WorkInfoEntriesCompanion.insert(
              sourceId: sourceId,
              workInfoJson: jsonEncode(data),
            ),
          );
    } catch (e) {
      Log.warning('write workInfo cache failed: $sourceId\n' 'error: $e');
    }
  }

  /// 纯数字部分（去掉 RJ/VJ/BJ 前缀）并去掉前导零：
  /// RJ01618607 → 1618607，与 asmr API 的 work id（数字型）一致。
  static String normalizeDigits(String s) =>
      s.replaceAll(RegExp(r'[^0-9]'), '').replaceFirst(RegExp(r'^0+'), '');

  /// 按纯数字 id 查找已缓存的 sourceId（汉化版原版跟踪时 id 可能不带 RJ 前缀）。
  /// 缓存条目数较少（百级），全量扫描可接受。
  Future<String?> findSourceIdByDigits(String digits) async {
    if (digits.isEmpty) return null;
    final normalized = normalizeDigits(digits);
    if (normalized.isEmpty) return null;
    try {
      final rows = await _db.select(_db.workInfoEntries).get();
      for (final row in rows) {
        if (normalizeDigits(row.sourceId) == normalized) {
          return row.sourceId;
        }
      }
    } catch (e) {
      Log.warning('findSourceIdByDigits failed: $digits\n' 'error: $e');
    }
    return null;
  }

  // ---------- tracks ----------

  Future<List<dynamic>?> getTracks(String sourceId) async {
    try {
      final entry = await (_db.select(_db.tracksEntries)
            ..where((t) => t.sourceId.equals(sourceId)))
          .getSingleOrNull();
      if (entry == null) return null;
      final decoded = jsonDecode(entry.tracksJson);
      return decoded is List ? decoded : null;
    } catch (e) {
      Log.warning('read tracks cache failed: $sourceId\n' 'error: $e');
      return null;
    }
  }

  Future<void> saveTracks(String sourceId, List<dynamic> data) async {
    try {
      await _db.into(_db.tracksEntries).insertOnConflictUpdate(
            TracksEntriesCompanion.insert(
              sourceId: sourceId,
              tracksJson: jsonEncode(data),
            ),
          );
    } catch (e) {
      Log.warning('write tracks cache failed: $sourceId\n' 'error: $e');
    }
  }

  /// 统计每个作品音轨树中 `type == 'audio'` 的节点数（与 tracks.dart 判定一致）。
  /// 用于 CV 统计里的「歌曲数」聚合，避免逐个作品联网或扫描目录。
  /// key 为 sourceId，value 为 audio 节点总数（含嵌套 folder 内的）。
  Future<Map<String, int>> getAudioTrackCounts() async {
    try {
      final rows = await _db.select(_db.tracksEntries).get();
      final result = <String, int>{};
      for (final row in rows) {
        final decoded = jsonDecode(row.tracksJson);
        if (decoded is! List) continue;
        result[row.sourceId] = _countAudioNodes(decoded);
      }
      return result;
    } catch (e) {
      Log.warning('get audio track counts failed\n' 'error: $e');
      return {};
    }
  }

  /// 递归遍历音轨 JSON 树：folder 节点展开 children，其余按 type 判定。
  static int _countAudioNodes(List<dynamic> nodes) {
    var count = 0;
    for (final node in nodes) {
      if (node is! Map) continue;
      if (node['type'] == 'audio') count++;
      final children = node['children'];
      if (children is List) {
        count += _countAudioNodes(children);
      }
    }
    return count;
  }

  // ---------- covers (BLOB) ----------

  Future<Uint8List?> getCover(String sourceId) async {
    try {
      final entry = await (_db.select(_db.coverEntries)
            ..where((t) => t.sourceId.equals(sourceId)))
          .getSingleOrNull();
      if (entry == null) return null;
      return entry.coverBytes;
    } catch (e) {
      Log.warning('read cover cache failed: $sourceId\n' 'error: $e');
      return null;
    }
  }

  Future<void> saveCover(String sourceId, Uint8List bytes) async {
    try {
      await _db.into(_db.coverEntries).insertOnConflictUpdate(
            CoverEntriesCompanion.insert(
              sourceId: sourceId,
              coverBytes: bytes,
            ),
          );
    } catch (e) {
      Log.warning('write cover cache failed: $sourceId\n' 'error: $e');
    }
  }

  Future<bool> hasCover(String sourceId) async {
    return await getCover(sourceId) != null;
  }

  // ---------- 管理 ----------

  /// 已缓存 workInfo 的条目数
  Future<int> getCacheCount() async {
    try {
      return await _db.workInfoEntries.count().getSingle();
    } catch (e) {
      Log.warning('count workInfo cache failed\n' 'error: $e');
      return 0;
    }
  }

  /// 已缓存 tracks 的条目数
  Future<int> getTracksCount() async {
    try {
      return await _db.tracksEntries.count().getSingle();
    } catch (e) {
      Log.warning('count tracks cache failed\n' 'error: $e');
      return 0;
    }
  }

  /// 已缓存封面的条目数
  Future<int> getCoverCount() async {
    try {
      return await _db.coverEntries.count().getSingle();
    } catch (e) {
      Log.warning('count cover cache failed\n' 'error: $e');
      return 0;
    }
  }

  /// 清空全部缓存
  Future<void> clearCache() async {
    try {
      await _db.transaction(() async {
        await _db.delete(_db.workInfoEntries).go();
        await _db.delete(_db.tracksEntries).go();
        await _db.delete(_db.coverEntries).go();
      });
    } catch (e) {
      Log.error('clear cache failed\n' 'error: $e');
      rethrow;
    }
  }

  /// 删除单个作品的全部缓存条目
  Future<void> removeEntry(String sourceId) async {
    try {
      await _db.transaction(() async {
        await (_db.delete(_db.workInfoEntries)
              ..where((t) => t.sourceId.equals(sourceId)))
            .go();
        await (_db.delete(_db.tracksEntries)
              ..where((t) => t.sourceId.equals(sourceId)))
            .go();
        await (_db.delete(_db.coverEntries)
              ..where((t) => t.sourceId.equals(sourceId)))
            .go();
      });
    } catch (e) {
      Log.warning('remove cache entry failed: $sourceId\n' 'error: $e');
      rethrow;
    }
  }

  // ---------- 导入导出（复制 .db 文件） ----------

  /// 导出缓存数据库文件到 [targetPath]。
  /// 先做 WAL checkpoint 把可能的 WAL 内容合并回主文件，再整体复制
  /// （drift NativeDatabase 默认非 WAL 模式，此调用为无害保险）。
  Future<void> exportTo(String targetPath) async {
    try {
      await _db.customStatement('PRAGMA wal_checkpoint(FULL)');
      final src = File(dbPath);
      if (!await src.exists()) throw StateError('缓存数据库不存在: $dbPath');
      await src.copy(targetPath);
      Log.info('cache exported: $dbPath -> $targetPath');
    } catch (e) {
      Log.error('export cache failed\n' 'error: $e');
      rethrow;
    }
  }

  /// 从 [sourcePath] 导入缓存数据库文件：
  /// 关闭当前连接 → 覆盖数据库文件 → 重新打开连接。
  Future<void> importFrom(String sourcePath) async {
    final src = File(sourcePath);
    if (!await src.exists()) throw StateError('导入文件不存在: $sourcePath');
    try {
      await _db.close();
      final file = File(dbPath);
      if (await file.exists()) {
        await file.delete();
      }
      await file.create(recursive: true);
      await src.copy(dbPath);
      _db = CacheDatabase.fromPath(dbPath);
      // 打开新连接（触发建表/迁移校验）
      await _db.doWhenOpened((_) async {});
      Log.info('cache imported: $sourcePath -> $dbPath');
    } catch (e) {
      Log.error('import cache failed\n' 'error: $e');
      rethrow;
    }
  }
}
