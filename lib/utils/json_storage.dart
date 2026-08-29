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
    final data = await readJsonWithBackup(filePath);
    if (data == null) return {};
    return data;
  }

  Future<void> write(Map<String, dynamic> data) async {
    await writeJsonAtomic(filePath, data);
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

/// 通用原子 JSON 写，避免应用异常退出时留下半截 JSON：
///
/// 1. 写 `<target>.tmp` 并 flush；
/// 2. 读回解析验证（写出的内容必须能完整解析）；
/// 3. 旧 target → `<target>.bak`（保留上一份已知完好内容）；
/// 4. tmp → target（同目录 rename，近似原子）。
Future<void> writeJsonAtomic(String path, Object? value) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  final tmpPath = '$path.tmp';
  final bakPath = '$path.bak';
  final contents = json.encode(value);

  // 1. tmp 写入 + flush
  final tmp = File(tmpPath);
  final sink = tmp.openWrite();
  try {
    sink.write(contents);
    await sink.flush();
  } finally {
    await sink.close();
  }

  try {
    // 2. 解析验证：tmp 必须能完整解析回来
    json.decode(await tmp.readAsString());

    // 3. 旧 target → .bak（先删旧 bak，Windows 上 rename 不能覆盖已存在目标）
    final bak = File(bakPath);
    if (await bak.exists()) {
      await bak.delete();
    }
    if (await file.exists()) {
      await file.rename(bakPath);
    }

    // 4. tmp → target
    await tmp.rename(file.path);
  } catch (e) {
    // 校验或替换失败：保留原 target 与 .bak 不动，清理 tmp 后抛出
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
    throw Exception('atomic json write failed: $path\nerror: $e');
  }
}

/// 读 JSON（配合 [writeJsonAtomic] 的恢复语义）：
///
/// - 正式文件存在且可解析 → 直接返回；
/// - 正式文件缺失或损坏 → 尝试 `.bak`；命中时记录 warning 并把 .bak
///   自动恢复为正式文件；
/// - 两者都不可得 → 返回 null（由调用方决定默认值）。
Future<Map<String, dynamic>?> readJsonWithBackup(String path) async {
  final bakPath = '$path.bak';

  Future<Map<String, dynamic>?> tryParse(File file) async {
    try {
      final decoded = json.decode(await file.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  final file = File(path);
  if (await file.exists()) {
    final parsed = await tryParse(file);
    if (parsed != null) return parsed;
  }

  // 正式文件缺失/损坏：回退 .bak
  final bak = File(bakPath);
  if (!await bak.exists()) return null;
  final restored = await tryParse(bak);
  if (restored == null) {
    Log.error('read json failed and backup is also corrupted: $path');
    return null;
  }
  Log.warning('json file corrupted, restored from backup: $path');
  try {
    await bak.copy(file.path);
  } catch (e) {
    Log.warning('restore json from backup failed: $path\n' 'error: $e');
  }
  return restored;
}
