import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('onNotifyOnCompleteChanged 能够更新 provider 状态', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final service = container.read(uiServiceProvider);

    expect(container.read(notifyOnCompleteProvider), isTrue);

    service.onNotifyOnCompleteChanged(false);
    expect(container.read(notifyOnCompleteProvider), isFalse);

    service.onNotifyOnCompleteChanged(true);
    expect(container.read(notifyOnCompleteProvider), isTrue);
  });

  test('onThemeModeChanged 能够更新 provider 状态', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final service = container.read(uiServiceProvider);

    expect(container.read(themeModeProvider), 'dark');

    service.onThemeModeChanged('light');
    expect(container.read(themeModeProvider), 'light');

    service.onThemeModeChanged('system');
    expect(container.read(themeModeProvider), 'system');
  });
}
