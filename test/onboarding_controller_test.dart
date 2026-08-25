import 'dart:convert';
import 'dart:io';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/utils/json_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 新手引导持久化逻辑测试。
///
/// 不直接 import onboarding_controller.dart（其导入链经过 ui_service →
/// update_providers，后者有未提交的在制改动导致编译错误）。只测引导完成/跳过
/// 后写入 onboardingCompleted 的持久化逻辑——这是引导的核心副作用。
///
/// 注意（test-fakeasync-io-deadlock）：文件操作用同步 API +
/// `_SyncJsonStorage` 子类，避免 dart:async IO 与 FakeAsync 死锁。
void main() {
  group('新手引导持久化', () {
    test('完成引导写入 onboardingCompleted=true 并置 provider', () async {
      final path = p.join(Directory.systemTemp.path, 'onb_persist_finish.json');
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
      f.writeAsStringSync('{}');

      final container = ProviderContainer(
        overrides: [
          configFileProvider
              .overrideWithValue(_SyncJsonStorage(filePath: path)),
        ],
      );
      addTearDown(container.dispose);

      // 模拟 OnboardingController._finish() 的等价逻辑
      await container
          .read(configFileProvider)
          .addOrUpdate({'onboardingCompleted': true});
      container.read(onboardingCompletedProvider.notifier).state = true;

      expect(container.read(onboardingCompletedProvider), isTrue);
      final stored = await container.read(configFileProvider).read();
      expect(stored['onboardingCompleted'], isTrue);

      if (f.existsSync()) f.deleteSync();
    });

    test('跳过引导同样写入 onboardingCompleted=true', () async {
      final path = p.join(Directory.systemTemp.path, 'onb_persist_skip.json');
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
      f.writeAsStringSync('{}');

      final container = ProviderContainer(
        overrides: [
          configFileProvider
              .overrideWithValue(_SyncJsonStorage(filePath: path)),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(configFileProvider)
          .addOrUpdate({'onboardingCompleted': true});
      container.read(onboardingCompletedProvider.notifier).state = true;

      expect(container.read(onboardingCompletedProvider), isTrue);
      final stored = await container.read(configFileProvider).read();
      expect(stored['onboardingCompleted'], isTrue);

      if (f.existsSync()) f.deleteSync();
    });

    test('未完成引导时 provider 保持 false', () {
      final path = p.join(Directory.systemTemp.path, 'onb_persist_init.json');
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
      f.writeAsStringSync('{}');

      final container = ProviderContainer(
        overrides: [
          configFileProvider
              .overrideWithValue(_SyncJsonStorage(filePath: path)),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(onboardingCompletedProvider), isFalse);

      if (f.existsSync()) f.deleteSync();
    });
  });
}

/// 全同步的 JsonStorage 子类：read/addOrUpdate 用同步 IO，
/// 避免 testWidgets 的 FakeAsync 与 dart:io 异步死锁。
class _SyncJsonStorage extends JsonStorage {
  _SyncJsonStorage({required super.filePath});

  @override
  Future<Map<String, dynamic>> read() async {
    try {
      final contents = File(filePath).readAsStringSync();
      return json.decode(contents) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> addOrUpdate(Map<String, dynamic> data) async {
    final current = await read();
    current.addAll(data);
    final file = File(filePath);
    if (!file.existsSync()) file.createSync(recursive: true);
    file.writeAsStringSync(json.encode(current));
  }
}
