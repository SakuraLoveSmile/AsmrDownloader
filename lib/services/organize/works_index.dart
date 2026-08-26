import 'dart:convert';
import 'dart:io';

import 'package:asmr_downloader/services/library/library_database.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

/// 下载作品注册表条目。
///
/// 记录本应用下载过的作品及其作品级元数据，供整理和作品库使用；
/// 不保存音轨明细，音轨/封面缓存由 cache 数据库按 sourceId 管理。
class WorkEntry {
  /// 作品 sourceId，如 RJ01619789
  final String sourceId;

  /// 下载根目录（downloadPath）
  final String dlPath;

  /// 作品目录名（如 cv-标题），与 [dlPath] 拼出下载目录
  final String dirName;

  /// 作品标题（下载时刻获取，整理时作为降级兜底）
  final String title;

  /// CV 名单，& 连接
  final String cvNames;

  /// 社团名
  final String circleName;

  /// 发行日期
  final String releaseDate;

  /// 流派标签
  final List<String> tags;

  /// 封面 URL
  final String coverUrl;

  /// 最近一次整理完成时间（ISO 8601），null = 未整理过
  final String? organizedAt;

  /// 最近一次手动编辑元数据的时间，null = 未手动编辑过。
  ///
  /// 非 null 时整理以本条目（手动）值为准，不被在线 workInfo 覆盖。
  final DateTime? manuallyEditedAt;

  /// 显式作品目录路径（如扁平外部导入目录 "RJ号 - CV - 标题"），空串表示
  /// 目录可按现有规则由 [dlPath]/[dirName]/[sourceId] 重建。
  ///
  /// 仅用于无法通过标准结构表达的目录：非空时 [sourceDir] 直接返回该值，
  /// 不再拼接三层路径。
  final String sourceDirOverride;

  /// 最近一次校验结果摘要（如「3 首缺内嵌歌词、封面缺失」），null = 无缺陷。
  final String? verifyNote;

  /// 缺陷是否可通过重新整理修复（重跑 organizeEntry forceWavRewrite）。
  final bool? verifyRepairable;

  /// 最近一次校验时间，null = 从未校验。
  final DateTime? verifiedAt;

  const WorkEntry({
    required this.sourceId,
    required this.dlPath,
    required this.dirName,
    required this.title,
    required this.cvNames,
    this.circleName = '',
    this.releaseDate = '',
    this.tags = const [],
    this.coverUrl = '',
    this.organizedAt,
    this.manuallyEditedAt,
    this.sourceDirOverride = '',
    this.verifyNote,
    this.verifyRepairable,
    this.verifiedAt,
  });

  /// 下载目录：{dlPath}/{dirName}/{sourceId}；
  /// 设置了 [sourceDirOverride] 时直接使用该显式路径。
  String get sourceDir => sourceDirOverride.isNotEmpty
      ? sourceDirOverride
      : p.join(dlPath, dirName, sourceId);

  WorkEntry copyWith({
    String? dlPath,
    String? dirName,
    String? organizedAt,
    bool clearOrganizedAt = false,
    DateTime? manuallyEditedAt,
    String? sourceDirOverride,
    String? verifyNote,
    bool? verifyRepairable,
    DateTime? verifiedAt,
  }) {
    return WorkEntry(
      sourceId: sourceId,
      dlPath: dlPath ?? this.dlPath,
      dirName: dirName ?? this.dirName,
      title: title,
      cvNames: cvNames,
      circleName: circleName,
      releaseDate: releaseDate,
      tags: tags,
      coverUrl: coverUrl,
      organizedAt: clearOrganizedAt ? null : (organizedAt ?? this.organizedAt),
      manuallyEditedAt: manuallyEditedAt ?? this.manuallyEditedAt,
      sourceDirOverride: sourceDirOverride ?? this.sourceDirOverride,
      verifyNote: verifyNote ?? this.verifyNote,
      verifyRepairable: verifyRepairable ?? this.verifyRepairable,
      verifiedAt: verifiedAt ?? this.verifiedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'dlPath': dlPath,
        'dirName': dirName,
        'title': title,
        'cvNames': cvNames,
        'circleName': circleName,
        'releaseDate': releaseDate,
        'tags': tags,
        'coverUrl': coverUrl,
        'organizedAt': organizedAt,
        'manuallyEditedAt': manuallyEditedAt?.toIso8601String(),
        'sourceDirOverride': sourceDirOverride,
        'verifyNote': verifyNote,
        'verifyRepairable': verifyRepairable,
        'verifiedAt': verifiedAt?.toIso8601String(),
      };

  factory WorkEntry.fromJson(Map<String, dynamic> json) => WorkEntry(
        sourceId: json['sourceId']?.toString() ?? '',
        dlPath: json['dlPath']?.toString() ?? '',
        dirName: json['dirName']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        cvNames: json['cvNames']?.toString() ?? '',
        circleName: json['circleName']?.toString() ?? '',
        releaseDate: json['releaseDate']?.toString() ?? '',
        tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        coverUrl: json['coverUrl']?.toString() ?? '',
        organizedAt: json['organizedAt']?.toString(),
        manuallyEditedAt: json['manuallyEditedAt'] == null
            ? null
            : DateTime.tryParse(json['manuallyEditedAt'].toString()),
        sourceDirOverride: json['sourceDirOverride']?.toString() ?? '',
        verifyNote: json['verifyNote']?.toString(),
        verifyRepairable: json['verifyRepairable'] as bool?,
        verifiedAt: json['verifiedAt'] == null
            ? null
            : DateTime.tryParse(json['verifiedAt'].toString()),
      );
}

/// 下载作品注册表。
///
/// 新版本使用 SQLite/Drift 保存，旧版本的 [filePath] 只作为 JSON 迁移源保留。
/// 这样不会把数据库写进下载目录，也不会因为目录扫描失败而丢失作品元数据。
class WorksIndex {
  static const _legacyMigrationKey = 'legacy_works_index_json_imported_v1';

  /// 旧版 JSON 路径，保留公开属性以兼容设置/测试和迁移提示。
  final String filePath;

  late final LibraryDatabase database;
  late final bool _ownsDatabase;
  Future<void>? _migration;

  WorksIndex({required this.filePath, LibraryDatabase? database}) {
    this.database = database ??
        LibraryDatabase.fromPath(_databasePathForLegacyFile(filePath));
    _ownsDatabase = database == null;
  }

  static String _databasePathForLegacyFile(String legacyPath) {
    final dir = p.dirname(legacyPath);
    final name = p.basenameWithoutExtension(legacyPath);
    return p.join(dir, '$name.db');
  }

  Future<void> _ensureMigrated() {
    return _migration ??= _migrateLegacyJson();
  }

  Future<void> _migrateLegacyJson() async {
    final marker = await (database.select(database.libraryMeta)
          ..where((t) => t.key.equals(_legacyMigrationKey)))
        .getSingleOrNull();
    if (marker != null) return;

    final legacyEntries = <WorkEntry>[];
    final legacyFile = File(filePath);
    if (await legacyFile.exists()) {
      try {
        final decoded = jsonDecode(await legacyFile.readAsString());
        if (decoded is Map) {
          for (final raw in decoded.values) {
            if (raw is Map) {
              final entry = WorkEntry.fromJson(
                Map<String, dynamic>.from(raw),
              );
              if (entry.sourceId.isNotEmpty) legacyEntries.add(entry);
            }
          }
        }
        Log.info('migrating ${legacyEntries.length} works from $filePath');
      } catch (e) {
        // 损坏的旧 JSON 不应阻止新数据库启动；保留空索引供用户重新扫描。
        Log.warning('read legacy works index failed: $filePath\nerror: $e');
      }
    }

    await database.transaction(() async {
      for (final entry in legacyEntries) {
        await database.into(database.libraryWorks).insertOnConflictUpdate(
              _toCompanion(entry),
            );
      }
      await database.into(database.libraryMeta).insertOnConflictUpdate(
            LibraryMetaCompanion.insert(
              key: _legacyMigrationKey,
              value: DateTime.now().toIso8601String(),
            ),
          );
    });
  }

  static LibraryWorksCompanion _toCompanion(WorkEntry entry) {
    return LibraryWorksCompanion.insert(
      sourceId: entry.sourceId,
      dlPath: Value(entry.dlPath),
      dirName: Value(entry.dirName),
      title: Value(entry.title),
      cvNames: Value(entry.cvNames),
      circleName: Value(entry.circleName),
      releaseDate: Value(entry.releaseDate),
      tagsJson: Value(jsonEncode(entry.tags)),
      coverUrl: Value(entry.coverUrl),
      organizedAt: Value(entry.organizedAt),
      manuallyEditedAt: Value(entry.manuallyEditedAt),
      sourceDirOverride: Value(
        entry.sourceDirOverride.isEmpty ? null : entry.sourceDirOverride,
      ),
      verifyNote: Value(entry.verifyNote),
      verifyRepairable: Value(entry.verifyRepairable),
      verifiedAt: Value(entry.verifiedAt),
      updatedAt: Value(DateTime.now()),
    );
  }

  static WorkEntry _fromRow(LibraryWork row) {
    var tags = const <String>[];
    try {
      final decoded = jsonDecode(row.tagsJson);
      if (decoded is List) {
        tags = decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {
      // 坏的标签字段不应影响作品库其它字段。
    }
    return WorkEntry(
      sourceId: row.sourceId,
      dlPath: row.dlPath,
      dirName: row.dirName,
      title: row.title,
      cvNames: row.cvNames,
      circleName: row.circleName,
      releaseDate: row.releaseDate,
      tags: tags,
      coverUrl: row.coverUrl,
      organizedAt: row.organizedAt,
      manuallyEditedAt: row.manuallyEditedAt,
      sourceDirOverride: row.sourceDirOverride ?? '',
      verifyNote: row.verifyNote,
      verifyRepairable: row.verifyRepairable,
      verifiedAt: row.verifiedAt,
    );
  }

  /// 全部条目，按 sourceId 稳定排序。
  Future<List<WorkEntry>> list() async {
    await _ensureMigrated();
    final query = database.select(database.libraryWorks)
      ..orderBy([(t) => OrderingTerm.asc(t.sourceId)]);
    return (await query.get()).map(_fromRow).toList();
  }

  Future<WorkEntry?> get(String sourceId) async {
    await _ensureMigrated();
    final row = await (database.select(database.libraryWorks)
          ..where((t) => t.sourceId.equals(sourceId)))
        .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  /// 新增或更新条目。
  Future<void> upsert(WorkEntry entry) async {
    await _ensureMigrated();
    await database.into(database.libraryWorks).insertOnConflictUpdate(
          _toCompanion(entry),
        );
  }

  /// 手动编辑元数据后落库：与 [upsert] 等价，但显式把
  /// [WorkEntry.manuallyEditedAt] 置为当前时间。
  ///
  /// 编辑对话框使用；此后整理（单条/批量）以手动值为准，不被在线
  /// workInfo 覆盖。
  Future<void> updateMetadata(WorkEntry entry) async {
    // 保留既有校验状态：编辑对话框构造的条目不含校验字段，因此以注册表中
    // 已存的校验结果为准（缺失时退回调用方传入值）。元数据编辑不应清除缺陷记录。
    final existing = await get(entry.sourceId);
    await upsert(WorkEntry(
      sourceId: entry.sourceId,
      dlPath: entry.dlPath,
      dirName: entry.dirName,
      title: entry.title,
      cvNames: entry.cvNames,
      circleName: entry.circleName,
      releaseDate: entry.releaseDate,
      tags: entry.tags,
      coverUrl: entry.coverUrl,
      organizedAt: entry.organizedAt,
      manuallyEditedAt: DateTime.now(),
      sourceDirOverride: entry.sourceDirOverride,
      verifyNote: existing?.verifyNote ?? entry.verifyNote,
      verifyRepairable: existing?.verifyRepairable ?? entry.verifyRepairable,
      verifiedAt: existing?.verifiedAt ?? entry.verifiedAt,
    ));
  }

  /// 删除条目。不会删除媒体库扫描位置，也不会删除实际文件。
  Future<void> remove(String sourceId) async {
    await _ensureMigrated();
    await (database.delete(database.libraryWorks)
          ..where((t) => t.sourceId.equals(sourceId)))
        .go();
  }

  /// 记录整理完成时间。
  Future<void> markOrganized(String sourceId, {DateTime? time}) async {
    final entry = await get(sourceId);
    if (entry == null) return;
    await upsert(entry.copyWith(
        organizedAt: (time ?? DateTime.now()).toIso8601String()));
  }

  /// 统一写回校验状态（整理/批量校验/对话框共用，不依赖 VerifyWorkResult）。
  ///
  /// - [verifiedAt] 固定为当前时间；
  /// - [verifyNote] 为 null 表示「最近校验通过」，会清除旧的缺陷摘要；
  /// - [verifyRepairable] 标识缺陷是否可通过重新整理修复。
  /// 写回后再读取注册表返回最新 [WorkEntry]（含持久化校验字段）。
  Future<WorkEntry> updateVerifyState(
    WorkEntry entry, {
    required String? verifyNote,
    required bool verifyRepairable,
  }) async {
    final updated = entry.copyWith(
      verifiedAt: DateTime.now(),
      verifyNote: verifyNote,
      verifyRepairable: verifyRepairable,
    );
    await upsert(updated);
    // 回读以确保持久化字段（含其他并发更新）一致
    final stored = await get(entry.sourceId);
    return stored ?? updated;
  }

  /// 下载目录已不存在的条目。
  Future<List<WorkEntry>> listMissing() async {
    final entries = await list();
    return entries.where((e) => !Directory(e.sourceDir).existsSync()).toList();
  }

  /// 清理下载目录已不存在的条目，返回清理数量。
  Future<int> cleanMissing() async {
    final missing = await listMissing();
    for (final entry in missing) {
      await remove(entry.sourceId);
    }
    return missing.length;
  }

  /// 仅用于测试/Provider 关闭。
  Future<void> close() async {
    if (_ownsDatabase) await database.close();
  }
}
