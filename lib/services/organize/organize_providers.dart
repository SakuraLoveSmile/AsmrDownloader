import 'package:asmr_downloader/services/organize/organize_service.dart';
import 'package:asmr_downloader/services/organize/verify_service.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:asmr_downloader/services/library/library_database_providers.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// 下载作品注册表（应用数据目录，不污染下载目录）。
///
/// 旧版 works_index.json 由 WorksIndex 在首次访问时自动迁移到共享数据库。
final worksIndexProvider = Provider<WorksIndex>((ref) {
  return WorksIndex(
    filePath: p.join(getAppDataDir(), 'works_index.json'),
    database: ref.watch(libraryDatabaseProvider),
  );
});

/// 整理编排层
final organizeServiceProvider = Provider<OrganizeService>((ref) {
  return OrganizeService(ref);
});

/// 整理产物校验服务（只读检查内嵌歌词/封面）
final verifyServiceProvider = Provider<VerifyService>((ref) {
  return VerifyService(ref);
});
