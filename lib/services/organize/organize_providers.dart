import 'package:asmr_downloader/services/organize/organize_service.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// 下载作品注册表（应用数据目录，不污染下载目录）
final worksIndexProvider = Provider<WorksIndex>((ref) {
  return WorksIndex(filePath: p.join(getAppDataDir(), 'works_index.json'));
});

/// 整理编排层
final organizeServiceProvider = Provider<OrganizeService>((ref) {
  return OrganizeService(ref);
});
