import 'package:asmr_downloader/services/library/library_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 作品索引和媒体库扫描共用的 SQLite 数据库。
final libraryDatabaseProvider = Provider<LibraryDatabase>((ref) {
  final database = LibraryDatabase();
  ref.onDispose(database.close);
  return database;
});
