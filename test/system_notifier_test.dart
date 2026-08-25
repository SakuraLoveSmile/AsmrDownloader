import 'dart:io';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/ui/system_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('启用通知开关时调用系统通知脚本', () async {
    final calls = <List<String>>[];
    final container = ProviderContainer(
      overrides: [
        notifyOnCompleteProvider.overrideWith((ref) => true),
      ],
    );
    addTearDown(container.dispose);

    final notifier = SystemNotifier(
      container.readProviderElement(systemNotifierProvider),
      runner: (executable, arguments) async {
        calls.add([executable, ...arguments]);
        return ProcessResult(0, 0, '', '');
      },
    );

    await notifier.notify('测试标题', '测试内容');

    if (Platform.isMacOS) {
      expect(calls, hasLength(1));
      expect(calls.first.first, 'osascript');
      expect(calls.first.last,
          contains('display notification "测试内容" with title "测试标题"'));
    } else if (Platform.isWindows) {
      expect(calls, hasLength(1));
      expect(calls.first.first, 'powershell');
    }
  });

  test('禁用通知开关时不触发通知脚本', () async {
    final calls = <List<String>>[];
    final container = ProviderContainer(
      overrides: [
        notifyOnCompleteProvider.overrideWith((ref) => false),
      ],
    );
    addTearDown(container.dispose);

    final notifier = SystemNotifier(
      container.readProviderElement(systemNotifierProvider),
      runner: (executable, arguments) async {
        calls.add([executable, ...arguments]);
        return ProcessResult(0, 0, '', '');
      },
    );

    await notifier.notify('测试标题', '测试内容');
    expect(calls, isEmpty);
  });

  test('通知脚本执行异常时静默降级不抛出错误', () async {
    final container = ProviderContainer(
      overrides: [
        notifyOnCompleteProvider.overrideWith((ref) => true),
      ],
    );
    addTearDown(container.dispose);

    final notifier = SystemNotifier(
      container.readProviderElement(systemNotifierProvider),
      runner: (executable, arguments) async {
        throw const ProcessException('osascript', [], 'fail', 1);
      },
    );

    expect(() => notifier.notify('标题', '内容'), returnsNormally);
  });
}
