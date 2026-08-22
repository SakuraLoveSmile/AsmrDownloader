import 'dart:convert';
import 'dart:io';

import 'package:asmr_downloader/utils/log.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// 下载队列中的一个作品项。
///
/// [selectedTrackIds] 为 null 表示旧版队列文件没有保存选择信息，恢复时
/// 按全选处理；非 null（包括空列表）表示严格恢复用户入队时的勾选结果。
class DownloadQueueItem {
  DownloadQueueItem({
    required this.sourceId,
    Iterable<String>? selectedTrackIds,
  }) : selectedTrackIds = selectedTrackIds == null
            ? null
            : List.unmodifiable(selectedTrackIds);

  final String sourceId;
  final List<String>? selectedTrackIds;

  bool get hasSelectionSnapshot => selectedTrackIds != null;

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'selectedTrackIds': selectedTrackIds,
      };

  static DownloadQueueItem? fromJson(Object? value) {
    if (value is String) {
      // v0.10.7 及更早版本只保存 sourceId；null 表示兼容旧行为：全选。
      return value.isEmpty ? null : DownloadQueueItem(sourceId: value);
    }
    if (value is! Map) return null;

    final sourceId = value['sourceId']?.toString() ?? '';
    if (sourceId.isEmpty) return null;

    final rawIds = value['selectedTrackIds'];
    final selectedIds = rawIds is List
        ? rawIds.map((id) => id.toString()).where((id) => id.isNotEmpty)
        : null;
    return DownloadQueueItem(
      sourceId: sourceId,
      selectedTrackIds: selectedIds,
    );
  }
}

/// 下载队列持久化：保存待下载作品及其入队时勾选的文件 ID 有序列表。
/// 作品间串行执行，下载中可继续搜索并把新作品「加入队列」，
/// 当前作品下完后自动取队首继续。
///
/// 新格式：
/// `{ "items": [{"sourceId":"RJ00001","selectedTrackIds":["hash"]}] }`
/// 旧格式 `{ "items": ["RJ00001"] }` 仍可读取。
class DownloadQueue {
  final String filePath;

  DownloadQueue({required this.filePath});

  /// 写操作串行队列：add/remove/clear/popFront 都是读-改-写，
  /// 调用方常 fire-and-forget 连续调用，串行化避免互相覆盖。
  Future<void> _pendingWrite = Future.value();

  Future<Map<String, dynamic>> _readRaw() async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return {'items': <String>[]};
      final decoded = json.decode(await file.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
      return {'items': <String>[]};
    } catch (e) {
      Log.warning('read download queue failed: $filePath\n' 'error: $e');
      return {'items': <String>[]};
    }
  }

  Future<void> _writeRaw(Map<String, dynamic> data) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      await file.writeAsString(json.encode(data));
    } catch (e) {
      Log.error('write download queue failed: $filePath\n' 'error: $e');
    }
  }

  Future<List<DownloadQueueItem>> _readItems() async {
    final raw = await _readRaw();
    final items = raw['items'];
    if (items is List) {
      return [
        for (final item in items)
          if (DownloadQueueItem.fromJson(item) case final parsed?) parsed,
      ];
    }
    return <DownloadQueueItem>[];
  }

  Future<void> _writeItems(List<DownloadQueueItem> items) async {
    await _writeRaw({'items': items.map((item) => item.toJson()).toList()});
  }

  /// 读取当前队列。读取也要排在写操作之后，避免启动时的异步加载
  /// 把刚刚写入的条目覆盖掉。
  Future<List<DownloadQueueItem>> list() {
    return _pendingWrite.then((_) => _readItems());
  }

  /// 查看队首但不移除。
  Future<DownloadQueueItem?> peek() async {
    final items = await list();
    return items.isEmpty ? null : items.first;
  }

  /// 追加入队（去重），返回是否新增（已存在返回 false）。
  Future<bool> add(
    String sourceId, {
    Iterable<String>? selectedTrackIds,
  }) async {
    final task = _pendingWrite.then((_) async {
      final items = await _readItems();
      if (items.any((item) => item.sourceId == sourceId)) return false;
      items.add(DownloadQueueItem(
        sourceId: sourceId,
        selectedTrackIds: selectedTrackIds,
      ));
      await _writeItems(items);
      return true;
    });
    _pendingWrite = task.catchError((_) => false);
    return task;
  }

  Future<void> remove(String sourceId) async {
    final task = _pendingWrite.then((_) async {
      final items = await _readItems();
      final before = items.length;
      items.removeWhere((item) => item.sourceId == sourceId);
      if (items.length != before) {
        await _writeItems(items);
      }
    });
    _pendingWrite = task.catchError((_) {});
    return task;
  }

  Future<void> clear() async {
    final task = _pendingWrite.then((_) => _writeItems(<DownloadQueueItem>[]));
    _pendingWrite = task.catchError((_) {});
    return task;
  }

  /// 取出并移除队首 sourceId；队列空返回 null。
  Future<DownloadQueueItem?> popFront() async {
    DownloadQueueItem? popped;
    final task = _pendingWrite.then((_) async {
      final items = await _readItems();
      if (items.isEmpty) return null;
      popped = items.removeAt(0);
      await _writeItems(items);
      return popped;
    });
    _pendingWrite = task.catchError((_) => null);
    return task;
  }

  /// 仅当队首仍是 [expected] 时取出它。
  /// 队列页允许用户在元数据加载期间移除条目，因此下载器不能
  /// 在条目已经被用户移除后误取出下一个作品。
  Future<DownloadQueueItem?> popFrontIf(String expected) async {
    final task = _pendingWrite.then((_) async {
      final items = await _readItems();
      if (items.isEmpty || items.first.sourceId != expected) return null;
      final popped = items.removeAt(0);
      await _writeItems(items);
      return popped;
    });
    _pendingWrite = task.catchError((_) => null);
    return task;
  }
}

/// 下载队列文件路径（可被测试 override 到临时目录）
final downloadQueueFilePathProvider = Provider<String>((ref) {
  return p.join(getAppDataDir(), 'download_queue.json');
});

/// 下载队列状态管理：每次变更后更新 state 并落盘。
class DownloadQueueNotifier extends Notifier<List<DownloadQueueItem>> {
  late final DownloadQueue _queue;
  late final Future<void> _ready;
  var _mounted = true;

  @override
  List<DownloadQueueItem> build() {
    _queue = DownloadQueue(filePath: ref.read(downloadQueueFilePathProvider));
    _mounted = true;
    ref.onDispose(() => _mounted = false);

    // Notifier 必须同步返回初始 state，但所有写操作都会等待这次加载。
    // 否则「启动加载」与第一次点击加入队列会发生竞态，导致 UI 状态回退。
    _ready = _loadFromDisk();
    return <DownloadQueueItem>[];
  }

  Future<void> _loadFromDisk() async {
    final items = await _queue.list();
    if (_mounted) state = items;
  }

  /// 供下载管理器在应用启动早期安全地等待队列恢复。
  Future<void> waitUntilReady() => _ready;

  /// 追加入队（去重），返回是否新增。
  Future<bool> add(
    String sourceId, {
    Iterable<String>? selectedTrackIds,
  }) async {
    if (sourceId.trim().isEmpty) return false;
    final normalizedSelection = selectedTrackIds?.toList(growable: false);
    await _ready;
    final added = await _queue.add(
      sourceId,
      selectedTrackIds: normalizedSelection,
    );
    if (added && _mounted) {
      state = [
        ...state,
        DownloadQueueItem(
          sourceId: sourceId,
          selectedTrackIds: normalizedSelection,
        ),
      ];
    }
    return added;
  }

  Future<void> remove(String sourceId) async {
    await _ready;
    await _queue.remove(sourceId);
    if (_mounted) state = state.where((e) => e.sourceId != sourceId).toList();
  }

  Future<void> clear() async {
    await _ready;
    await _queue.clear();
    if (_mounted) state = <DownloadQueueItem>[];
  }

  /// 取出并移除队首；队列空返回 null。
  Future<DownloadQueueItem?> popFront() async {
    await _ready;
    final popped = await _queue.popFront();
    if (popped != null && _mounted) {
      state = state.skip(1).toList();
    }
    return popped;
  }

  /// 查看队首但不移除。
  Future<DownloadQueueItem?> peek() async {
    await _ready;
    return _queue.peek();
  }

  /// 仅当队首仍为 [expected] 时移除，并返回是否成功。
  Future<bool> popFrontIf(String expected) async {
    await _ready;
    final popped = await _queue.popFrontIf(expected);
    if (popped != null && _mounted) {
      state = state.where((e) => e.sourceId != expected).toList();
    }
    return popped != null;
  }
}

/// 下载队列 provider：当前待下载作品及其文件选择的有序列表。
final downloadQueueProvider =
    NotifierProvider<DownloadQueueNotifier, List<DownloadQueueItem>>(
        DownloadQueueNotifier.new);

/// 当前正在下载的作品 sourceId（下载中写入、结束置 null），
/// 供 UI 判断「加入队列」按钮是否需要禁用。
final currentDownloadingSourceIdProvider =
    StateProvider<String?>((ref) => null);
