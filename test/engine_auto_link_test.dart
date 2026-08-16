import 'dart:io';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:asmr_downloader/utils/json_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory testBase;
  late String configPath;

  setUp(() {
    testBase = Directory.systemTemp.createTempSync('engine_auto_link_test');
    configPath = p.join(testBase.path, 'config.json');
  });

  tearDown(() {
    testBase.deleteSync(recursive: true);
  });

  /// 构造一个「完整引擎」的假安装目录：infer.exe + VAD + 主模型
  Directory makeInstalledEngine({String dirName = 'engine'}) {
    final dir = Directory(p.join(testBase.path, dirName))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'infer.exe')).writeAsBytesSync([1]);
    final models = Directory(p.join(dir.path, 'models'))..createSync();
    File(p.join(models.path, 'whisper_vad.onnx')).writeAsBytesSync([2]);
    File(p.join(models.path, 'model.bin')).writeAsBytesSync([3]);
    return dir;
  }

  /// 配置存储指向临时文件，避免污染真实用户配置
  ProviderContainer makeContainer() => ProviderContainer(overrides: [
        configFileProvider.overrideWithValue(JsonStorage(filePath: configPath)),
      ]);

  test('配置缺失但安装目录引擎完整：autoLink 自动关联并持久化', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final engineDir = makeInstalledEngine();

    container.read(chickenRiceEngineInstallDirProvider.notifier).state =
        engineDir.path;
    // 模拟配置丢失：脚本路径为空
    container.read(chickenRiceScriptPathProvider.notifier).state = '';

    await container.read(uiServiceProvider).autoLinkInstalledEngine();

    expect(container.read(chickenRiceScriptPathProvider),
        p.join(engineDir.path, 'infer.exe'));
    // 设备为默认 auto 时按安装语义预置 cuda
    expect(container.read(chickenRiceDeviceProvider), 'cuda');
    // 持久化是异步 fire-and-forget，等待写入完成
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final saved = await JsonStorage(filePath: configPath).read();
    expect(saved['chickenRiceExePath'], p.join(engineDir.path, 'infer.exe'));
  });

  test('已有有效的手动配置：autoLink 不覆盖', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final engineDir = makeInstalledEngine();
    final manualScript = File(p.join(testBase.path, 'my.bat'))
      ..writeAsBytesSync([9]);

    container.read(chickenRiceScriptPathProvider.notifier).state =
        manualScript.path;
    container.read(chickenRiceEngineInstallDirProvider.notifier).state =
        engineDir.path;

    await container.read(uiServiceProvider).autoLinkInstalledEngine();

    expect(container.read(chickenRiceScriptPathProvider), manualScript.path);
  });

  test('引擎不完整（缺主模型）：不自动关联', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final dir = Directory(p.join(testBase.path, 'partial'))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'infer.exe')).writeAsBytesSync([1]);
    final models = Directory(p.join(dir.path, 'models'))..createSync();
    File(p.join(models.path, 'whisper_vad.onnx')).writeAsBytesSync([2]);

    container.read(chickenRiceEngineInstallDirProvider.notifier).state =
        dir.path;

    await container.read(uiServiceProvider).autoLinkInstalledEngine();

    expect(container.read(chickenRiceScriptPathProvider), isEmpty);
  });

  test('未记录安装目录：autoLink 直接跳过', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    await container.read(uiServiceProvider).autoLinkInstalledEngine();

    expect(container.read(chickenRiceScriptPathProvider), isEmpty);
  });

  test('linkInstalledEngine 可指定候选目录并回写安装目录配置', () async {
    final container = makeContainer();
    addTearDown(container.dispose);
    final engineDir = makeInstalledEngine(dirName: 'found_elsewhere');

    final exe = await container
        .read(uiServiceProvider)
        .linkInstalledEngine(installDir: engineDir.path);

    expect(exe, p.join(engineDir.path, 'infer.exe'));
    expect(container.read(chickenRiceEngineInstallDirProvider), engineDir.path);
  });
}
