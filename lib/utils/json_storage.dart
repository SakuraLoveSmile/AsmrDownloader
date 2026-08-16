import 'dart:io';
import 'dart:convert';

import 'package:asmr_downloader/utils/log.dart';

class JsonStorage {
  final String filePath;

  JsonStorage({required this.filePath});

  /// 写操作串行队列：addOrUpdate 是读-改-写，调用方常 fire-and-forget
  /// 连续多次调用（如安装完成后写多个配置项），并发执行会互相覆盖
  /// 导致配置项丢失；用队列串行化保证每次写入基于最新内容。
  Future<void> _pendingWrite = Future.value();

  Future<Map<String, dynamic>> read() async {
    try {
      final file = File(filePath);
      final contents = await file.readAsString();
      return json.decode(contents) as Map<String, dynamic>;
    } catch (e) {
      Log.error('read "$filePath" failed\n' 'error: $e');
      return {};
    }
  }

  Future<void> write(Map<String, dynamic> data) async {
    final file = File(filePath);
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    final contents = json.encode(data);
    await file.writeAsString(contents);
  }

  Future<void> addOrUpdate(Map<String, dynamic> data) async {
    final task = _pendingWrite.then((_) async {
      final currentData = await read();
      currentData.addAll(data);
      await write(currentData);
    });
    // 队列不因单次失败中断；异常仍抛给调用方
    _pendingWrite = task.catchError((_) {});
    return task;
  }
}
