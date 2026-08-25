import 'dart:io';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/library/works_library_service.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 作品库数据服务
final worksLibraryServiceProvider = Provider<WorksLibraryService>((ref) {
  return WorksLibraryService(ref);
});

/// 作品库列表（进入页面加载；整理/字幕/下载完成后 invalidate 刷新）
final worksLibraryProvider =
    FutureProvider.autoDispose<List<WorksListItem>>((ref) {
  return ref.watch(worksLibraryServiceProvider).listWorks();
});

/// 未整理作品数（作品库 tab badge 用；仅统计目录仍存在的条目）
final unorganizedCountProvider = FutureProvider<int>((ref) async {
  final entries = await ref.read(worksIndexProvider).list();
  final targetRoot = ref.read(navidromePathProvider);
  final organizer = ref.read(organizeServiceProvider);
  var count = 0;
  for (final e in entries) {
    if (Directory(e.sourceDir).existsSync() &&
        !await organizer.isOrganized(e,
            targetRoot: targetRoot,
            keepDirStructure: ref.read(keepOrganizeDirStructureProvider))) {
      count++;
    }
  }
  return count;
});
