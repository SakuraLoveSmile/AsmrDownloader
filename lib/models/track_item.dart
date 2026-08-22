import 'package:dio/dio.dart';

class TrackItem {
  String id;
  String type;
  String title;
  List<String> pathLs = [];
  bool selected = false;
  int depth = 0;

  TrackItem({
    required this.id,
    required this.type,
    required this.title,
  });

  TrackItem copyWith({
    String? id,
    String? type,
    String? title,
    List<String>? pathLs,
    bool? selected,
    int? depth,
  }) {
    return TrackItem(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
    )
      ..pathLs = pathLs ?? List<String>.of(this.pathLs)
      ..selected = selected ?? this.selected
      ..depth = depth ?? this.depth;
  }
}

class Folder extends TrackItem {
  List<TrackItem> children = [];

  Folder({
    required super.id,
    super.type = 'folder',
    required super.title,
  });

  @override
  Folder copyWith({
    String? id,
    String? type,
    String? title,
    List<String>? pathLs,
    bool? selected,
    int? depth,
    List<TrackItem>? children,
  }) {
    return Folder(
      id: id ?? this.id,
      title: title ?? this.title,
    )
      ..pathLs = pathLs ?? List<String>.of(this.pathLs)
      ..selected = selected ?? this.selected
      ..depth = depth ?? this.depth
      ..children =
          children ?? this.children.map((child) => child.copyWith()).toList();
  }

  void setSelection(bool value) {
    selected = value;
    for (final child in children) {
      if (child is Folder) {
        child.setSelection(value);
      } else {
        child.selected = value;
      }
    }
  }

  TrackItem? search(String id) {
    for (final child in children) {
      if (child.id == id) {
        return child;
      }
      if (child is Folder) {
        final result = child.search(id);
        if (result != null) {
          return result;
        }
      }
    }
    return null;
  }
}

/// 返回作品中当前勾选的文件 ID。
///
/// 文件 ID 来自音轨接口的 hash，跨重新搜索/重新构建音轨树仍保持稳定，
/// 适合写入下载队列持久化；目录本身不写入，因为目录勾选最终代表的是
/// 其下所有文件的选择结果。
List<String> selectedFileIds(Folder root) {
  final ids = <String>[];

  void walk(TrackItem item) {
    if (item is Folder) {
      for (final child in item.children) {
        walk(child);
      }
    } else if (item is FileAsset && item.selected) {
      ids.add(item.id);
    }
  }

  walk(root);
  return ids;
}

/// 将持久化的文件选择恢复到重新构建的音轨树。
///
/// [selectedIds] 为 null 表示旧版队列条目没有选择信息，按旧行为默认
/// 全选；非 null（包括空集合）表示严格恢复用户当时的勾选结果。
void applySelectedFileIds(Folder root, Iterable<String>? selectedIds) {
  if (selectedIds == null) {
    root.setSelection(true);
    return;
  }

  final selected = selectedIds.toSet();

  bool walk(TrackItem item) {
    if (item is Folder) {
      var allSelected = item.children.isNotEmpty;
      for (final child in item.children) {
        allSelected = walk(child) && allSelected;
      }
      item.selected = allSelected;
      return allSelected;
    }

    final isSelected = item is FileAsset && selected.contains(item.id);
    item.selected = isSelected;
    return isSelected;
  }

  walk(root);
}

enum DownloadStatus { notStarted, downloading, completed, failed, canceled }

class FileAsset extends TrackItem {
  String mediaStreamUrl;
  String mediaDownloadUrl;
  int size;

  String savePath;
  DownloadStatus status;
  double progress;
  CancelToken cancelToken;

  FileAsset({
    required super.id,
    required super.type,
    required super.title,
    required this.mediaStreamUrl,
    required this.mediaDownloadUrl,
    required this.size,
    this.savePath = '',
    this.status = DownloadStatus.notStarted,
    this.progress = 0.0,
    CancelToken? cancelToken,
  }) : cancelToken = cancelToken ?? CancelToken();

  @override
  FileAsset copyWith({
    String? id,
    String? type,
    String? title,
    List<String>? pathLs,
    bool? selected,
    int? depth,
    String? mediaStreamUrl,
    String? mediaDownloadUrl,
    int? size,
    String? savePath,
    DownloadStatus? status,
    double? progress,
    CancelToken? cancelToken,
  }) {
    return FileAsset(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      mediaStreamUrl: mediaStreamUrl ?? this.mediaStreamUrl,
      mediaDownloadUrl: mediaDownloadUrl ?? this.mediaDownloadUrl,
      size: size ?? this.size,
      savePath: savePath ?? this.savePath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      cancelToken: cancelToken ?? CancelToken(),
    )
      ..pathLs = pathLs ?? List<String>.of(this.pathLs)
      ..selected = selected ?? this.selected
      ..depth = depth ?? this.depth;
  }
}
