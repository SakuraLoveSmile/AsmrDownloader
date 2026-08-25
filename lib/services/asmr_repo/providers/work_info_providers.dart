import 'dart:typed_data';

import 'package:asmr_downloader/services/asmr_repo/providers/api_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/tracks_providers.dart';
import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/organize/navidrome_organizer.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/utils/asmr_url_parser.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 缓存优先的 workInfo：命中本地缓存则不再请求 API；
/// 未命中（或 forceRefresh）时请求 API 并写入缓存。
/// 作品元数据发布后基本不变（仅 dl_count 变化，可接受长期缓存）。
final workInfoProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final id = ref.watch(idProvider);
  if (id == null) {
    return null;
  }

  final sourceId = ref.watch(sourceIdProvider) ?? '';
  final cache = ref.read(cacheServiceProvider);
  final forceRefresh = ref.read(forceRefreshProvider);

  if (!forceRefresh && sourceId.isNotEmpty) {
    final cached = await cache.getWorkInfo(sourceId);
    if (cached != null) {
      Log.info('workInfo cache hit: $sourceId');
      return cached;
    }
  }

  Log.info('fetch workInfo, id: $id');
  final api = ref.watch(asmrApiProvider);
  final data = await api.getWorkInfoOrThrow(id);
  if (data != null && sourceId.isNotEmpty) {
    await cache.saveWorkInfo(sourceId, data);
  }
  return data;
});

/// 标题降级链：work info → tracks 携带的 workTitle → URL 目录面包屑 → sourceId。
/// work info 接口获取不到数据时仍有保底标题用于下载目录与音乐标签，
/// 不会出现空标题（此前会退化成 "dlPath/-" 或空专辑标签）。
final titleProvider = Provider<String>((ref) {
  final sourceId = ref.watch(sourceIdProvider) ?? '';

  // 1. work info 标题
  final workTitle = ref.watch(workInfoProvider).maybeWhen(
        data: (data) => data?['title']?.toString() ?? '',
        orElse: () => '',
      );
  if (workTitle.isNotEmpty) return workTitle;

  // 2. tracks 数据里携带的 workTitle（work info 挂了但 tracks 成功时）
  final tracksTitle = ref.watch(rawTracksProvider).maybeWhen(
        data: (data) => findWorkTitleInTracks(data) ?? '',
        orElse: () => '',
      );
  if (tracksTitle.isNotEmpty) return tracksTitle;

  // 3. URL 目录面包屑（path 参数）
  final urlTitle =
      fallbackTitleFromTreePath(ref.watch(workTreePathProvider), sourceId);
  if (urlTitle.isNotEmpty) return urlTitle;

  // 4. 最后保底 sourceId
  return sourceId;
});

/// 从 tracks 树中找第一个非空 workTitle（音轨节点都携带作品标题）。
String? findWorkTitleInTracks(List<dynamic>? tracks) {
  if (tracks == null) return null;
  for (final node in tracks) {
    if (node is! Map) continue;
    final workTitle = node['workTitle'];
    if (workTitle is String && workTitle.isNotEmpty) return workTitle;
    final children = node['children'];
    if (children is List) {
      final found = findWorkTitleInTracks(children);
      if (found != null) return found;
    }
  }
  return null;
}

/// 社团名（已解析为原始社团名）。
///
/// 简体中文版等汉化作品的 `circle.name` 是汉化组名而非真实社团，
/// 这里复用 [NavidromeOrganizer.resolveCircleName] 跟踪到原版取真实社团名
/// （缓存优先，与整理阶段同源），使下载页展示/注册表/作品库全程一致。
/// 原版作品或解析失败时 fallback 到当前 circle 名。
final circleNameProvider = FutureProvider<String>((ref) async {
  // workInfo 加载失败（网络错误等）时降级为空，与原同步版 maybeWhen 行为一致
  final workInfo =
      await ref.watch(workInfoProvider.future).catchError((_) => null);
  final rawCircle = (workInfo?['circle']?['name']?.toString()) ?? '';
  if (rawCircle.isEmpty) return '';
  return NavidromeOrganizer.resolveCircleName(
    workInfo: workInfo,
    fallbackCircle: rawCircle,
    fetchWorkInfo: ref.read(organizeServiceProvider).fetchWorkInfoCached,
  );
});

final cvLsProvider = Provider<List<String>>((ref) {
  final workInfo = ref.watch(workInfoProvider);
  return workInfo.maybeWhen(
    data: (data) {
      if (data == null) {
        return [];
      }
      return (data['vas'] as List).map((e) => e['name'].toString()).toList();
    },
    orElse: () => [],
  );
});

final coverUrlProvider = Provider<String>((ref) {
  final workInfo = ref.watch(workInfoProvider);
  return workInfo.maybeWhen(
    data: (data) {
      if (data == null) {
        return '';
      }
      return data['mainCoverUrl'].toString();
    },
    orElse: () => '',
  );
});

/// 缓存优先的封面字节：命中本地 BLOB 缓存则不再请求网络；
/// 未命中（或 forceRefresh）时按封面 URL 拉取并写入缓存。
final coverBytesProvider = FutureProvider<Uint8List?>((ref) async {
  final coverUrl = ref.watch(coverUrlProvider);
  if (coverUrl.isEmpty) {
    return null;
  }

  final sourceId = ref.watch(sourceIdProvider) ?? '';
  final cache = ref.read(cacheServiceProvider);
  final forceRefresh = ref.read(forceRefreshProvider);

  if (!forceRefresh && sourceId.isNotEmpty) {
    final cached = await cache.getCover(sourceId);
    if (cached != null) {
      Log.info('cover cache hit: $sourceId');
      return cached;
    }
  }

  Log.info('fetch cover bytes, url: $coverUrl');
  final api = ref.watch(asmrApiProvider);
  final bytes = await api.getCoverBytes(coverUrl);
  if (bytes != null && sourceId.isNotEmpty) {
    await cache.saveCover(sourceId, bytes);
  }
  return bytes;
});

final tagLsProvider = Provider<List<String>>((ref) {
  final workInfo = ref.watch(workInfoProvider);
  return workInfo.maybeWhen(
    data: (data) {
      if (data == null) {
        return [];
      }
      return (data['tags'] as List)
          .map((e) => e['i18n']['zh-cn']['name'].toString())
          .toList();
    },
    orElse: () => [],
  );
});

final releaseDateProvider = Provider<String>((ref) {
  final workInfo = ref.watch(workInfoProvider);
  return workInfo.maybeWhen(
    data: (data) {
      if (data == null) {
        return '';
      }
      return data['release'].toString();
    },
    orElse: () => '',
  );
});

final dlCountProvider = Provider<int>((ref) {
  final workInfo = ref.watch(workInfoProvider);
  return workInfo.maybeWhen(
    data: (data) {
      if (data == null) {
        return 0;
      }
      return data['dl_count'] as int;
    },
    orElse: () => 0,
  );
});
