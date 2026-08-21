import 'dart:convert';
import 'dart:io';

import 'package:asmr_downloader/utils/log.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// 下载队列持久化：仅存待下载作品的 sourceId 有序列表。
/// 作品间串行执行，下载中可继续搜索并把新作品「加入队列」，
/// 当前作品下完后自动取队首继续。格式：{"items": ["RJ00001", ...]}
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

  Future<List<String>> _readItems() async {
    final raw = await _readRaw();
    final items = raw['items'];
    if (items is List) {
      return items.map((e) => e.toString()).toList();
    }
    return <String>[];
  }

  Future<void> _writeItems(List<String> items) async {
    await _writeRaw({'items': items});
  }

  /// 读取当前队列。读取也要排在写操作之后，避免启动时的异步加载
  /// 把刚刚写入的条目覆盖掉。
  Future<List<String>> list() {
    return _pendingWrite.then((_) => _readItems());
  }

  /// 查看队首但不移除。
  Future<String?> peek() async {
    final items = await list();
    return items.isEmpty ? null : items.first;
  }

  /// 追加入队（去重），返回是否新增（已存在返回 false）。
  Future<bool> add(String sourceId) async {
    final task = _pendingWrite.then((_) async {
      final items = await _readItems();
      if (items.contains(sourceId)) return false;
      items.add(sourceId);
      await _writeItems(items);
      return true;
    });
    _pendingWrite = task.catchError((_) => false);
    return task;
  }

  Future<void> remove(String sourceId) async {
    final task = _pendingWrite.then((_) async {
      final items = await _readItems();
      if (items.remove(sourceId)) {
        await _writeItems(items);
      }
    });
    _pendingWrite = task.catchError((_) {});
    return task;
  }

  Future<void> clear() async {
    final task = _pendingWrite.then((_) => _writeItems(<String>[]));
    _pendingWrite = task.catchError((_) {});
    return task;
  }

  /// 取出并移除队首 sourceId；队列空返回 null。
  Future<String?> popFront() async {
    String? popped;
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
  Future<String?> popFrontIf(String expected) async {
    final task = _pendingWrite.then((_) async {
      final items = await _readItems();
      if (items.isEmpty || items.first != expected) return null;
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
class DownloadQueueNotifier extends Notifier<List<String>> {
  late final DownloadQueue _queue;
  late final Future<void> _ready;
  var _mounted = true;

  @override
  List<String> build() {
    _queue = DownloadQueue(filePath: ref.read(downloadQueueFilePathProvider));
    _mounted = true;
    ref.onDispose(() => _mounted = false);

    // Notifier 必须同步返回初始 state，但所有写操作都会等待这次加载。
    // 否则「启动加载」与第一次点击加入队列会发生竞态，导致 UI 状态回退。
    _ready = _loadFromDisk();
    return <String>[];
  }

  Future<void> _loadFromDisk() async {
    final items = await _queue.list();
    if (_mounted) state = items;
  }

  /// 供下载管理器在应用启动早期安全地等待队列恢复。
  Future<void> waitUntilReady() => _ready;

  /// 追加入队（去重），返回是否新增。
  Future<bool> add(String sourceId) async {
    if (sourceId.trim().isEmpty) return false;
    await _ready;
    final added = await _queue.add(sourceId);
    if (added && _mounted) state = [...state, sourceId];
    return added;
  }

  Future<void> remove(String sourceId) async {
    await _ready;
    await _queue.remove(sourceId);
    if (_mounted) state = state.where((e) => e != sourceId).toList();
  }

  Future<void> clear() async {
    await _ready;
    await _queue.clear();
    if (_mounted) state = <String>[];
  }

  /// 取出并移除队首；队列空返回 null。
  Future<String?> popFront() async {
    await _ready;
    final popped = await _queue.popFront();
    if (popped != null && _mounted) {
      state = state.where((e) => e != popped).toList();
    }
    return popped;
  }

  /// 查看队首但不移除。
  Future<String?> peek() async {
    await _ready;
    return _queue.peek();
  }

  /// 仅当队首仍为 [expected] 时移除，并返回是否成功。
  Future<bool> popFrontIf(String expected) async {
    await _ready;
    final popped = await _queue.popFrontIf(expected);
    if (popped != null && _mounted) {
      state = state.where((e) => e != popped).toList();
    }
    return popped != null;
  }
}

/// 下载队列 provider：当前待下载作品的 sourceId 有序列表。
final downloadQueueProvider =
    NotifierProvider<DownloadQueueNotifier, List<String>>(
        DownloadQueueNotifier.new);

/// 当前正在下载的作品 sourceId（下载中写入、结束置 null），
/// 供 UI 判断「加入队列」按钮是否需要禁用。
final currentDownloadingSourceIdProvider =
    StateProvider<String?>((ref) => null);
