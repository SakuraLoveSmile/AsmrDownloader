import 'dart:convert';
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

  test('原子写：成功后保留 .bak（上一份已知完好内容）且无 .tmp 残留', () async {
    final storage = JsonStorage(filePath: configPath);

    await storage.write({'v': 1});
    await storage.write({'v': 2});

    expect(await JsonStorage(filePath: configPath).read(), {'v': 2});
    expect(File('$configPath.bak').existsSync(), isTrue);
    expect(json.decode(await File('$configPath.bak').readAsString()), {'v': 1});
    expect(File('$configPath.tmp').existsSync(), isFalse);
  });

  test('读取恢复：正式文件损坏时自动回退 .bak 并恢复正式文件', () async {
    final storage = JsonStorage(filePath: configPath);

    await storage.write({'v': 1});
    await storage.write({'v': 2});
    // 模拟异常退出留下的半截 JSON
    await File(configPath).writeAsString('{"v": 2');

    // .bak 是上一次成功写入（v:1），损坏的最后一次写入丢失
    final restored = await JsonStorage(filePath: configPath).read();
    expect(restored, {'v': 1});
    // 自动恢复：正式文件已可正常解析
    expect(json.decode(await File(configPath).readAsString()), {'v': 1});
  });

  test('读取恢复：正式文件与 .bak 均不可用时返回空配置', () async {
    await JsonStorage(filePath: configPath).write({'v': 1});
    await File(configPath).writeAsString('{broken');
    await File('$configPath.bak').writeAsString('also broken');

    expect(await JsonStorage(filePath: configPath).read(), <String, dynamic>{});
  });

  test('读取：文件不存在（首次运行）返回空配置且不报错', () async {
    expect(await JsonStorage(filePath: configPath).read(), <String, dynamic>{});
  });
}
