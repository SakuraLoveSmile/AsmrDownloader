import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/services/asmr_repo/parse_tracks.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/api_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/tracks_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/work_info_providers.dart';
import 'package:asmr_downloader/services/download/download_manager.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:asmr_downloader/utils/source_id.dart';
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
  // RJ/VJ/BJ 前缀编号直接走作品直查；纯数字/关键字才搜索
  if (searchText == null || SourceId.isPrefixed(searchText)) {
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
  final normalized = SourceId.normalize(searchText);
  if (normalized != null) {
    return SourceId.digits(normalized);
  }

  final searchResult = ref.watch(searchResultProvider);
  return searchResult.maybeWhen(
    data: _firstWorkId,
    orElse: () => null,
  );
});

final sourceIdProvider = Provider<String?>((ref) {
  final searchText = ref.watch(searchTextProvider);
  if (searchText == null) {
    return null;
  }
  final normalized = SourceId.normalize(searchText);
  if (normalized != null) {
    return normalized;
  }

  final searchResult = ref.watch(searchResultProvider);
  return searchResult.maybeWhen(
    data: (searchData) => _firstWorkId(searchData, key: 'source_id'),
    orElse: () => null,
  );
});

/// 从搜索结果取第一个作品字段；空结果/结构异常返回 null，禁止裸取 [0]。
String? _firstWorkId(Map<String, dynamic>? searchData, {String key = 'id'}) {
  final works = searchData?['works'];
  if (works is! List || works.isEmpty) return null;
  final first = works.first;
  if (first is! Map) return null;
  return first[key]?.toString();
}

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

/// 并行下载时当前正在下载的文件名列表，按任务队列顺序展示。
final activeFileNamesProvider = StateProvider<List<String>>((ref) => const []);

/// 当前/最近一次下载的作品 sourceId。下载页不依赖当前搜索结果，
/// 因此搜索切换后仍能显示真正正在处理的作品。
final lastDownloadSourceIdProvider = StateProvider<String?>((ref) => null);

/// 已完成下载的文件数（并行下载后语义由「开始数」改为「完成数」）。
final currentDlNoProvider = StateProvider<int>((ref) => 0);
final totalTaskCntProvider = StateProvider<int>((ref) => 0);

/// 本轮下载的总字节数（0 表示服务端未给出文件大小）。
final totalBytesProvider = StateProvider<int>((ref) => 0);

/// 已下载字节数（已完成文件 + 在途文件的增量），由 DownloadManager 实时更新。
final downloadedBytesProvider = StateProvider<int>((ref) => 0);

/// 单个文件的进度分段，用于分段进度条展示。
class DownloadSegment {
  const DownloadSegment({
    required this.title,
    required this.size,
    required this.fraction,
    required this.status,
    required this.speed,
  });

  final String title;

  /// 文件总字节数（未知时为 0）
  final int size;

  /// 该文件自身进度 0.0 ~ 1.0
  final double fraction;

  final DownloadStatus status;

  /// 该文件当前下载速度（bytes/s），仅下载中有意义
  final double speed;
}

/// 本轮全部任务的分段进度，按任务队列顺序，由 DownloadManager 实时更新。
final downloadSegmentsProvider =
    StateProvider<List<DownloadSegment>>((ref) => const []);
