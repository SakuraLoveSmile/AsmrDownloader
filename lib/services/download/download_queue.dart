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

  Future<List<String>> list() => _readItems();

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
}

/// 下载队列文件路径（可被测试 override 到临时目录）
final downloadQueueFilePathProvider = Provider<String>((ref) {
  return p.join(getAppDataDir(), 'download_queue.json');
});

/// 下载队列状态管理：每次变更后更新 state 并落盘。
class DownloadQueueNotifier extends Notifier<List<String>> {
  late final DownloadQueue _queue;

  @override
  List<String> build() {
    _queue = DownloadQueue(filePath: ref.read(downloadQueueFilePathProvider));
    // 异步从磁盘加载初始内容并同步到 state（构造时先返回空列表）
    _queue.list().then((items) {
      if (items.isNotEmpty) state = items;
    });
    return <String>[];
  }

  /// 追加入队（去重），返回是否新增。
  Future<bool> add(String sourceId) async {
    final added = await _queue.add(sourceId);
    if (added) state = [...state, sourceId];
    return added;
  }

  Future<void> remove(String sourceId) async {
    await _queue.remove(sourceId);
    state = state.where((e) => e != sourceId).toList();
  }

  Future<void> clear() async {
    await _queue.clear();
    state = <String>[];
  }

  /// 取出并移除队首；队列空返回 null。
  Future<String?> popFront() async {
    final popped = await _queue.popFront();
    if (popped != null) {
      state = state.where((e) => e != popped).toList();
    }
    return popped;
  }
}

/// 下载队列 provider：当前待下载作品的 sourceId 有序列表。
final downloadQueueProvider =
    NotifierProvider<DownloadQueueNotifier, List<String>>(
        DownloadQueueNotifier.new);

/// 当前正在下载的作品 sourceId（下载中写入、结束置 null），
/// 供 UI 判断「加入队列」按钮是否需要禁用。
final currentDownloadingSourceIdProvider = StateProvider<String?>((ref) => null);
