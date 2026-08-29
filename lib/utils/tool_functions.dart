import 'dart:convert';
import 'dart:io';

import 'package:asmr_downloader/utils/source_id.dart';
import 'package:path/path.dart' as p;

/// 输入合法性：RJ/VJ/BJ 前缀编号或纯数字（关键字搜索兜底）均放行。
/// 前缀判断统一收口到 [SourceId]，避免 VJ/BJ 只在部分路径被识别。
bool isSourceIdValid(String sourceId) {
  final value = sourceId.trim();
  return SourceId.isPrefixed(value) || RegExp(r'^\d+$').hasMatch(value);
}

/// 目录扫描：识别作品目录名中的 RJ/VJ/BJ 号（如 RJ01234567）。
/// 返回规范化大写 sourceId（如 RJ12345678），否则 null。
///
/// 规则：
/// - 目录名必须以 RJ / VJ / BJ 开头（如 "RJ01077805 - CV - 标题"）；
/// - 编号长度必须为 6～10 位；
/// - 编号后允许标题、CV 等非数字内容（如 "RJ12345678_cover"）；
/// - `(?!\d)` 防止将超过 10 位的编号截断匹配；
/// - 仍要求前缀紧贴 6~10 位数字，纯数字目录（如年份 "2024"）不误识别。
String? matchSourceIdFromDirName(String dirName) {
  final m = RegExp(r'^(RJ|VJ|BJ)(\d{6,10})(?!\d)', caseSensitive: false)
      .firstMatch(dirName.trim());
  if (m == null) return null;
  return '${m.group(1)!.toUpperCase()}${m.group(2)}';
}

/// 智能截断文件夹名（整理用）：
/// - 码点数与 UTF-8 字节数都不超限时原样返回；
/// - 超限时先按 [maxChars] 截断码点，再逐码点回退，
///   保证「结果 + …」的 UTF-8 字节数 ≤ [maxUtf8Bytes]
///   （防 emoji 等 4 字节字符突破 macOS 255 字节组件限制）；
/// - 清理截断处残留的空白/分隔符/标点，追加 …（U+2026）；
/// - 裁剪后为空时返回空串（由调用方兜底）。
String smartTruncate(String name, {int maxChars = 80, int maxUtf8Bytes = 240}) {
  final suffix = '…';
  var runes = name.runes.toList();
  if (runes.length <= maxChars && utf8.encode(name).length <= maxUtf8Bytes) {
    return name;
  }

  if (runes.length > maxChars) {
    runes = runes.sublist(0, maxChars);
  }
  var out = String.fromCharCodes(runes);
  while (utf8.encode(out + suffix).length > maxUtf8Bytes && runes.isNotEmpty) {
    runes.removeLast();
    out = String.fromCharCodes(runes);
  }
  // 清理截断处残留的空白/分隔符/标点（避免出现 "标题 - "、"标题、" 之类）
  out = out.replaceFirst(RegExp(r'[\s\-_—–、。，,;:：·…~]+$'), '');
  if (out.isEmpty) return '';
  return '$out$suffix';
}

/// 应用数据目录：
/// macOS 使用 ~/Library/Application Support/AsmrDownloader（CWD 是 /，相对路径写不进去）
/// Windows 保持相对路径（应用目录内）
String? _cachedAppDataDir;

/// 应用数据目录。
///
/// - macOS：`~/Library/Application Support/AsmrDownloader`；
/// - Windows：程序目录存在 `portable.flag` 时为便携模式，数据随程序目录；
///   否则使用 `%APPDATA%/AsmrDownloader`。旧版本默认把数据写在程序目录，
///   首次切换到系统目录时会自动复制旧数据（原目录保留，不删除）。
String getAppDataDir() {
  final cached = _cachedAppDataDir;
  if (cached != null) return cached;

  final dir = _resolveAppDataDir();
  _cachedAppDataDir = dir;
  return dir;
}

String _resolveAppDataDir() {
  if (Platform.isMacOS) {
    final home = Platform.environment['HOME'];
    if (home != null) {
      return p.join(home, 'Library', 'Application Support', 'AsmrDownloader');
    }
    return '.';
  }
  if (Platform.isWindows) {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    if (File(p.join(exeDir, 'portable.flag')).existsSync()) {
      return exeDir;
    }
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) return exeDir;
    final systemDir = p.join(appData, 'AsmrDownloader');
    // 旧版本数据在程序目录：首次迁移到系统目录（旧文件保留）
    migrateLegacyAppDataSync(legacyDir: exeDir, targetDir: systemDir);
    return systemDir;
  }
  return '.';
}

/// 旧版应用数据迁移（Windows 程序目录 → 系统数据目录）。
///
/// 仅当旧目录存在 `config.json` 且新目录尚无 `config.json` 时执行；
/// 复制 config.json / library / cache / download_queue.json / debug，
/// 旧数据原样保留，绝不删除。失败静默（新目录照常使用，不阻断启动）。
void migrateLegacyAppDataSync({
  required String legacyDir,
  required String targetDir,
}) {
  try {
    final legacyConfig = File(p.join(legacyDir, 'config.json'));
    if (!legacyConfig.existsSync()) return;
    if (File(p.join(targetDir, 'config.json')).existsSync()) return;

    const entries = [
      'config.json',
      'library',
      'cache',
      'download_queue.json',
      'debug',
    ];
    for (final name in entries) {
      final src = p.join(legacyDir, name);
      final dst = p.join(targetDir, name);
      if (File(src).existsSync()) {
        File(dst).parent.createSync(recursive: true);
        File(src).copySync(dst);
      } else if (Directory(src).existsSync()) {
        _copyDirectorySync(Directory(src), Directory(dst));
      }
    }
  } catch (_) {
    // 迁移失败不阻断启动
  }
}

void _copyDirectorySync(Directory src, Directory dst) {
  for (final entity in src.listSync(recursive: true)) {
    final rel = p.relative(entity.path, from: src.path);
    final target = p.join(dst.path, rel);
    if (entity is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (entity is File) {
      File(target).parent.createSync(recursive: true);
      entity.copySync(target);
    }
  }
}

String getLegalWindowsName(String name) {
  return name
      .replaceAll(RegExp(r'[<>:"/\\|?*]'), '') // 移除非法字符
      .replaceAll(RegExp(r'\.+$'), '') // 移除末尾句点
      .trim(); // 移除前后空格
}

String getSizeString(int bytes) {
  final kb = 1024;
  final mb = kb * 1024;
  final gb = mb * 1024;

  if (bytes < kb) {
    return '$bytes B';
  } else if (bytes < mb) {
    return '${(bytes / kb).toStringAsFixed(2)} KB';
  } else if (bytes < gb) {
    return '${(bytes / mb).toStringAsFixed(2)} MB';
  } else {
    return '${(bytes / gb).toStringAsFixed(2)} GB';
  }
}
