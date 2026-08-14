import 'dart:io';

import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

part 'cache_database.g.dart';

/// workInfo 缓存表 — 缓存 api.getWorkInfo(id) 的原始响应。
/// 作品元数据发布后基本不变（仅 dl_count 变化，可接受长期缓存），
/// 存原始 JSON 而非拆分字段，便于 API 结构变化与 provider 直接消费。
class WorkInfoEntries extends Table {
  /// 主键：作品 sourceId，如 "RJ01619789"
  TextColumn get sourceId => text()();

  /// 原始 API JSON 响应
  TextColumn get workInfoJson => text()();

  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {sourceId};
}

/// tracks 缓存表 — 缓存 api.getTracks(id) 的原始响应。
class TracksEntries extends Table {
  TextColumn get sourceId => text()();

  /// 原始 API JSON 响应
  TextColumn get tracksJson => text()();

  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {sourceId};
}

/// 封面缓存表 — 缓存封面图片二进制字节。
class CoverEntries extends Table {
  TextColumn get sourceId => text()();

  /// 封面图片二进制（BLOB）
  BlobColumn get coverBytes => blob()();

  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {sourceId};
}

/// 本地缓存数据库（drift/SQLite）：
/// 数据库文件位于 `{appDataDir}/cache/asmr_cache.db`，
/// 导入导出只需复制单个 .db 文件（drift NativeDatabase 默认非 WAL 日志模式，
/// 无活动事务时主文件即完整快照）。
@DriftDatabase(tables: [WorkInfoEntries, TracksEntries, CoverEntries])
class CacheDatabase extends _$CacheDatabase {
  /// 默认数据库文件路径：`{appDataDir}/cache/asmr_cache.db`
  static String defaultDbPath() =>
      p.join(getAppDataDir(), 'cache', 'asmr_cache.db');

  /// 默认实例（应用数据目录）
  CacheDatabase() : this.fromPath(defaultDbPath());

  /// 指定数据库文件路径（测试/导入导出用）
  CacheDatabase.fromPath(this.dbFilePath) : super(_openConnection(dbFilePath)) {
    _silenceMultipleDatabaseWarning();
  }

  /// 测试用：自定义 executor（如 NativeDatabase.memory()）
  CacheDatabase.forTesting(super.executor, {this.dbFilePath = ':memory:'}) {
    _silenceMultipleDatabaseWarning();
  }

  /// 导入缓存时会先关闭旧连接再新建实例（同一数据库文件的两次打开），
  /// 这是 importFrom 的有意设计，关闭 drift 的重复实例告警。
  static void _silenceMultipleDatabaseWarning() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  }

  /// 数据库文件路径
  final String dbFilePath;

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection(String dbPath) {
    final file = File(dbPath);
    if (!file.existsSync()) {
      file.createSync(recursive: true);
    }
    return NativeDatabase(file);
  }
}
