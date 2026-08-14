import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/services/asmr_repo/parse_tracks.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/api_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/tracks_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/work_info_providers.dart';
import 'package:asmr_downloader/services/download/download_manager.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:path/path.dart' as p;

final downloadManagerProvider = Provider((ref) => DownloadManager(ref));

final voiceWorkPathProvider = Provider<String>((ref) {
  final downloadPath = ref.watch(downloadPathProvider);
  final title = ref.watch(titleProvider);
  final cvLs = ref.watch(cvLsProvider);

  // cv1&cv2&...&cvn-title（cv 为空时省略，避免目录名出现孤立的 '-'）
  final dirName = getLegalWindowsName(
      [cvLs.join('&'), title].where((s) => s.isNotEmpty).join('-'));
  return p.join(downloadPath, dirName);
});

final searchTextProvider = StateProvider<String?>((ref) => null);

/// 从粘贴的 asmr.one 作品页 URL 中解析出的音轨树目录面包屑
/// （path 查询参数），work info 获取失败时用作保底标签。
final workTreePathProvider = StateProvider<List<String>>((ref) => const []);

final searchResultProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final searchText = ref.watch(searchTextProvider);
  if (searchText == null || searchText.startsWith('RJ')) {
    return null;
  }

  Log.info('search $searchText');
  final api = ref.watch(asmrApiProvider);
  return api.search(content: searchText);
});

final idProvider = Provider<String?>((ref) {
  final searchText = ref.watch(searchTextProvider);
  if (searchText == null) {
    return null;
  }
  if (searchText.startsWith('RJ')) {
    return searchText.replaceAll(RegExp(r'[^0-9]'), '');
  }

  final searchResult = ref.watch(searchResultProvider);
  return searchResult.maybeWhen(
    data: (searchData) => searchData?['works'][0]['id'].toString(),
    orElse: () => null,
  );
});

final sourceIdProvider = Provider<String?>((ref) {
  final searchText = ref.watch(searchTextProvider);
  if (searchText == null) {
    return null;
  }
  if (searchText.startsWith('RJ')) {
    return searchText;
  }

  final searchResult = ref.watch(searchResultProvider);
  return searchResult.maybeWhen(
    data: (searchData) => searchData?['works'][0]['source_id'].toString(),
    orElse: () => null,
  );
});

final rootFolderProvider = StateProvider<Folder?>((ref) {
  final rawTracks = ref.watch(rawTracksProvider);
  final sourceId = ref.watch(sourceIdProvider);
  if (sourceId == null) {
    return null;
  }

  return rawTracks.maybeWhen(
      data: (data) {
        if (data == null) {
          return null;
        }
        return Folder(id: sourceId, title: sourceId)
          ..children = getTrackItems(data);
      },
      orElse: () => null);
});

final dlStatusProvider = StateProvider((ref) => DownloadStatus.notStarted);

/// 下载速度（bytes/s），下载中由 DownloadManager 实时更新
final downloadSpeedProvider = StateProvider<double>((ref) => 0);

/// 下载剩余时间，下载中由 DownloadManager 实时更新
final downloadEtaProvider = StateProvider<Duration>((ref) => Duration.zero);

final processProvider = StateProvider<double>((ref) => 0);

final currentFileNameProvider = StateProvider<String>((ref) => '');

final currentDlNoProvider = StateProvider<int>((ref) => 0);
final totalTaskCntProvider = StateProvider<int>((ref) => 0);
