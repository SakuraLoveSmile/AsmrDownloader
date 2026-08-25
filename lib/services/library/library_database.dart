import 'dart:io';

import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

part 'library_database.g.dart';

/// 应用已知的下载作品。
///
/// 这张表替代旧版 works_index.json。它只保存作品级信息，不保存音轨明细；
/// 音轨和封面仍由 cache 数据库按 sourceId 缓存。
class LibraryWorks extends Table {
  TextColumn get sourceId => text()();
  TextColumn get dlPath => text().withDefault(const Constant(''))();
  TextColumn get dirName => text().withDefault(const Constant(''))();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get cvNames => text().withDefault(const Constant(''))();
  TextColumn get circleName => text().withDefault(const Constant(''))();
  TextColumn get releaseDate => text().withDefault(const Constant(''))();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  TextColumn get coverUrl => text().withDefault(const Constant(''))();
  TextColumn get organizedAt => text().nullable()();

  /// 显式作品目录路径（扁平外部导入等无法按 {dlPath}/{dirName}/{sourceId}
  /// 重建的目录），null = 空串（按标准结构重建）。
  TextColumn get sourceDirOverride => text().nullable()();

  /// 最近一次手动编辑元数据的时间，null = 未手动编辑过。
  ///
  /// 非 null 时整理以注册表手动值为准（标题/CV/社团/发行日期/标签），
  /// 不再被在线 workInfo 覆盖。
  DateTimeColumn get manuallyEditedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {sourceId};
}

/// 轻量媒体库扫描结果。
///
/// 每个 sourceId 在同一个扫描根目录下只保留一个最浅目录，避免 NAS 中
/// 同一作品存在多个副本时膨胀索引。matchedPath 只用于展示/定位，不会递归
/// 扫描音频、字幕或封面文件。
class MediaLibraryLocations extends Table {
  TextColumn get sourceId => text()();
  TextColumn get rootPath => text()();
  TextColumn get matchedPath => text()();
  IntColumn get depth => integer().withDefault(const Constant(0))();
  DateTimeColumn get scannedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {sourceId, rootPath};
}

/// 媒体库扫描根目录的状态。
///
/// 根目录临时不可用时不删除 locations，只记录错误；这样 NAS 未挂载时
/// 仍可知道其中曾经有哪些 RJ 作品，并继续避免重复下载。
class MediaLibraryRoots extends Table {
  TextColumn get rootPath => text()();
  DateTimeColumn get lastScannedAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {rootPath};
}

/// 数据库内部迁移标记。
class LibraryMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [LibraryWorks, MediaLibraryLocations, MediaLibraryRoots, LibraryMeta],
)
class LibraryDatabase extends _$LibraryDatabase {
  LibraryDatabase() : this.fromPath(defaultDbPath());

  LibraryDatabase.fromPath(this.dbFilePath)
      : super(_openConnection(dbFilePath)) {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  }

  LibraryDatabase.forTesting(super.executor, {this.dbFilePath = ':memory:'});

  final String dbFilePath;

  static String defaultDbPath() =>
      p.join(getAppDataDir(), 'library', 'asmr_library.db');

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(libraryWorks, libraryWorks.manuallyEditedAt);
          }
          if (from < 3) {
            await m.addColumn(libraryWorks, libraryWorks.sourceDirOverride);
          }
        },
      );

  static QueryExecutor _openConnection(String dbPath) {
    final file = File(dbPath);
    if (!file.existsSync()) file.createSync(recursive: true);
    return NativeDatabase(file);
  }
}
