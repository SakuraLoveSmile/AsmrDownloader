import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/pages/media_library/components/media_library_settings_dialog.dart';
import 'package:asmr_downloader/services/cache/media_library_settings.dart';
import 'package:asmr_downloader/utils/json_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryJsonStorage extends JsonStorage {
  _MemoryJsonStorage() : super(filePath: 'memory://config');

  Map<String, dynamic> values = {};

  @override
  Future<Map<String, dynamic>> read() async => Map.of(values);

  @override
  Future<void> addOrUpdate(Map<String, dynamic> data) async {
    values = {...values, ...data};
  }
}

void main() {
  test('统一请求间隔使用固定选项并能格式化', () {
    expect(mediaLibraryRequestIntervalOptions, hasLength(5));
    expect(
      formatMediaLibraryRequestInterval(const Duration(milliseconds: 500)),
      '500ms / 次请求',
    );
    expect(
      formatMediaLibraryRequestInterval(const Duration(seconds: 5)),
      '5 秒 / 次请求',
    );
  });

  testWidgets('媒体库设置入口修改后更新 provider 并持久化', (tester) async {
    final storage = _MemoryJsonStorage();
    final container = ProviderContainer(overrides: [
      configFileProvider.overrideWithValue(storage),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: MediaLibrarySettingsDialog(),
          ),
        ),
      ),
    );

    expect(find.text('媒体库设置'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<Duration>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 秒 / 次请求').last);
    await tester.pump();

    expect(
      container.read(mediaLibraryRequestIntervalProvider),
      const Duration(seconds: 5),
    );
    expect(storage.values['mediaLibraryRequestIntervalMs'], 5000);
  });
}
