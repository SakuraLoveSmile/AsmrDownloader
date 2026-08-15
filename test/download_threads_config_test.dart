import 'dart:io';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:asmr_downloader/utils/json_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('默认线程数为 4，修改后写入配置持久化', () async {
    final tempDir =
        Directory.systemTemp.createTempSync('dl_threads_config_test');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final configPath = p.join(tempDir.path, 'config.json');

    final container = ProviderContainer(overrides: [
      configFileProvider.overrideWithValue(JsonStorage(filePath: configPath)),
    ]);
    addTearDown(container.dispose);

    expect(container.read(downloadThreadsProvider), 4);

    container.read(uiServiceProvider).onDownloadThreadsChanged(8);
    expect(container.read(downloadThreadsProvider), 8);

    // onDownloadThreadsChanged 内部持久化是异步 fire-and-forget，等待写入完成
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final saved = await JsonStorage(filePath: configPath).read();
    expect(saved['downloadThreads'], 8);
  });

  test('可选线程值包含 1/2/4/8/16，非法值不会作为默认值', () {
    expect(downloadThreadOptions, [1, 2, 4, 8, 16]);
  });

  test('默认并行文件数为 2，修改后写入配置持久化', () async {
    final tempDir = Directory.systemTemp.createTempSync('parallel_config_test');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final configPath = p.join(tempDir.path, 'config.json');

    final container = ProviderContainer(overrides: [
      configFileProvider.overrideWithValue(JsonStorage(filePath: configPath)),
    ]);
    addTearDown(container.dispose);

    expect(container.read(parallelDownloadCountProvider), 2);
    expect(parallelDownloadOptions, [1, 2, 3, 4]);
    expect(maxTotalDownloadConnections, 16);

    container.read(uiServiceProvider).onParallelDownloadCountChanged(3);
    expect(container.read(parallelDownloadCountProvider), 3);

    await Future<void>.delayed(const Duration(milliseconds: 100));
    final saved = await JsonStorage(filePath: configPath).read();
    expect(saved['parallelDownloadCount'], 3);
  });
}
