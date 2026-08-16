import 'dart:io';

import 'package:asmr_downloader/utils/json_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late String configPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('json_storage_test');
    configPath = p.join(tempDir.path, 'config.json');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('并发 addOrUpdate 不丢键（读-改-写串行化）', () async {
    final storage = JsonStorage(filePath: configPath);

    // 模拟安装完成后连续 fire-and-forget 写多个配置项
    for (var i = 0; i < 8; i++) {
      storage.addOrUpdate({'key$i': i});
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final saved = await JsonStorage(filePath: configPath).read();
    for (var i = 0; i < 8; i++) {
      expect(saved['key$i'], i, reason: 'key$i 不应被并发写入覆盖丢失');
    }
  });

  test('后写的同名键覆盖先写的', () async {
    final storage = JsonStorage(filePath: configPath);

    await storage.addOrUpdate({'a': 1});
    await storage.addOrUpdate({'a': 2});

    final saved = await JsonStorage(filePath: configPath).read();
    expect(saved['a'], 2);
  });
}
