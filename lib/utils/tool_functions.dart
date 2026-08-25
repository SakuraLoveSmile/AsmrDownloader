import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

bool isSourceIdValid(String sourceId) =>
    RegExp(r'^(RJ|VJ|BJ)?\d+$', caseSensitive: false).hasMatch(sourceId);

/// 批量整理目录扫描：识别形如 RJ01234567 / VJ12345678 的目录名。
/// 返回规范化大写 sourceId（如 RJ12345678），否则 null。
/// 要求字母前缀 + 6~10 位数字，避免把纯数字目录（如年份 "2024"）误识别成作品。
String? matchSourceIdFromDirName(String dirName) {
  final m = RegExp(r'^(RJ|VJ|BJ)(\d{6,10})$', caseSensitive: false)
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
String getAppDataDir() {
  if (Platform.isMacOS) {
    final home = Platform.environment['HOME'];
    if (home != null) {
      return p.join(home, 'Library', 'Application Support', 'AsmrDownloader');
    }
  }
  return '.';
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
