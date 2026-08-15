import 'dart:io';

import 'package:asmr_downloader/utils/log.dart';
import 'package:asmr_downloader/utils/vtt_to_lrc.dart';
import 'package:path/path.dart' as p;

/// VTT 字幕 → LRC 歌词批量转换（作品库行内「转歌词」功能）。
///
/// 与整理链路一致的字幕命名约定：
/// - `foo.vtt` → `foo.lrc`；
/// - `foo.mp3.vtt` → `foo.mp3.lrc`（带音频扩展名时保留）。
/// 仅转换「有 .vtt 且无同名 .lrc」的文件，已有 .lrc 不覆盖。
class VttConverter {
  /// 目录内所有「有 .vtt 且无同名 .lrc」的 vtt 文件（递归）。
  static List<File> findConvertibleVtts(String dir) {
    final result = <File>[];
    if (!Directory(dir).existsSync()) return result;

    final lrcNames = <String>{};
    for (final f in _allFiles(dir)) {
      if (p.extension(f.path).toLowerCase() == '.lrc') {
        lrcNames.add(p.basename(f.path).toLowerCase());
      }
    }

    for (final f in _allFiles(dir)) {
      if (p.extension(f.path).toLowerCase() != '.vtt') continue;
      final base = p.basename(f.path).toLowerCase();
      final lrcName = '${base.substring(0, base.length - 4)}.lrc';
      if (lrcNames.contains(lrcName)) continue;
      result.add(f);
    }
    return result;
  }

  /// 转换目录内所有可转换的 vtt → lrc，返回成功转换数量。
  static Future<int> convertAll(String dir) async {
    var count = 0;
    for (final vtt in findConvertibleVtts(dir)) {
      try {
        final content = await vtt.readAsString();
        final lrc = vttToLrc(content);
        if (lrc == null) {
          Log.warning('vtt to lrc: no cue, skip ${vtt.path}');
          continue;
        }
        final base = p.basename(vtt.path);
        final lrcFile = File(p.join(
            vtt.parent.path, '${base.substring(0, base.length - 4)}.lrc'));
        await lrcFile.writeAsString(lrc);
        count++;
        Log.info('vtt to lrc: ${lrcFile.path}');
      } catch (e) {
        Log.warning('vtt to lrc failed: ${vtt.path}\n' 'error: $e');
      }
    }
    return count;
  }

  static Iterable<File> _allFiles(String dir) sync* {
    final stack = <Directory>[Directory(dir)];
    while (stack.isNotEmpty) {
      final dir2 = stack.removeLast();
      List<FileSystemEntity> children;
      try {
        children = dir2.listSync(followLinks: false);
      } catch (_) {
        continue;
      }
      for (final entity in children) {
        if (entity is Directory) {
          final name = p.basename(entity.path);
          if (name.startsWith('.')) continue;
          stack.add(entity);
        } else if (entity is File) {
          yield entity;
        }
      }
    }
  }
}
