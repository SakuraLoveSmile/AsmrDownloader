import 'dart:io';

import 'package:asmr_downloader/services/organize/works_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('scanner_test');
  });

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  File touch(String rel) {
    final f = File(p.join(root.path, rel));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync('x');
    return f;
  }

  test('平铺在下载根目录的 RJ 目录（dirName 为空）', () async {
    touch('RJ12345678/track.wav');
    final found = await scanDownloadRoot(dlRoot: root.path);
    expect(found.length, 1);
    expect(found.first.sourceId, 'RJ12345678');
    expect(found.first.dlPath, root.path);
    expect(found.first.dirName, '');
  });

  test('嵌套在作品目录下的 RJ 目录（dirName = 父目录名）', () async {
    touch('cv1&cv2-标题/RJ87654321/a.wav');
    final found = await scanDownloadRoot(dlRoot: root.path);
    expect(found.length, 1);
    expect(found.first.sourceId, 'RJ87654321');
    expect(found.first.dirName, 'cv1&cv2-标题');
    expect(
        found.first.sourceDir, p.join(root.path, 'cv1&cv2-标题', 'RJ87654321'));
  });

  test('VJ/BJ 前缀识别、小写前缀规范化', () async {
    touch('vj123456/a.wav');
    touch('bj234567/b.wav');
    final found = await scanDownloadRoot(dlRoot: root.path);
    expect(found.map((e) => e.sourceId).toSet(), {'VJ123456', 'BJ234567'});
  });

  test('放宽：带 CV/标题后缀的 RJ 目录也被识别', () async {
    // NAS/手工整理的目录名可能是 "RJ111111 - CV - 标题" 等
    touch('RJ111111 - CV - 标题/a.wav');
    touch('RJ222222 精选/b.wav');
    final found = await scanDownloadRoot(dlRoot: root.path);
    expect(found.map((e) => e.sourceId).toSet(), {'RJ111111', 'RJ222222'});
    expect(found.firstWhere((e) => e.sourceId == 'RJ111111').dirName, '');
  });

  test('排除 excludeRoot（整理目标目录不被当作源）', () async {
    touch('RJ111111/a.wav');
    // 整理目标目录（可能是下载目录的子目录）里的 RJ 目录不算源
    touch('navidrome_lib/RJ222222/b.wav');
    final found = await scanDownloadRoot(
        dlRoot: root.path, excludeRoot: p.join(root.path, 'navidrome_lib'));
    expect(found.map((e) => e.sourceId), ['RJ111111']);
  });

  test('同一 sourceId 多处出现取最浅路径', () async {
    touch('RJ333333/a.wav');
    touch('deep/nested/RJ333333/b.wav');
    final found = await scanDownloadRoot(dlRoot: root.path);
    expect(found.length, 1);
    expect(found.first.dirName, '');
  });

  test('纯数字目录（如年份）不误识别', () async {
    touch('2024/a.wav');
    touch('12345/b.wav');
    final found = await scanDownloadRoot(dlRoot: root.path);
    expect(found, isEmpty);
  });

  test('超过最大深度不扫描', () async {
    touch('a/b/c/d/RJ444444/a.wav');
    final found = await scanDownloadRoot(dlRoot: root.path, maxDepth: 2);
    expect(found, isEmpty);
    final deep = await scanDownloadRoot(dlRoot: root.path, maxDepth: 6);
    expect(deep.map((e) => e.sourceId), contains('RJ444444'));
  });
}
