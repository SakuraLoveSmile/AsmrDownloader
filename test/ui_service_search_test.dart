import 'package:asmr_downloader/services/asmr_repo/providers/tracks_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/work_info_providers.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 用户调研示例 URL：path 参数是音轨树目录面包屑
  const exampleUrl =
      'https://asmr-200.com/work/RJ01619789?path=%5B%22RJ01619789%22,%22%E8%88%94%E8%80%B3ONLY%E9%9F%B3%E8%BD%A8%22%5D#work-tree';

  ProviderContainer makeContainer() {
    final container = ProviderContainer(overrides: [
      // 模拟 work info / tracks 全部获取失败（降级模式）
      workInfoProvider.overrideWith((ref) async => null),
      rawTracksProvider.overrideWith((ref) async => null),
    ]);
    return container;
  }

  test('粘贴作品页 URL：提取 sourceId 与目录面包屑，标题降级到面包屑', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final result = await container.read(uiServiceProvider).search(exampleUrl);

    expect(result, 'RJ01619789');
    expect(container.read(searchTextProvider), 'RJ01619789');
    expect(container.read(workTreePathProvider), ['RJ01619789', '舔耳ONLY音轨']);

    await container.read(workInfoProvider.future);
    await container.read(rawTracksProvider.future);
    // 降级链：work info(null) → tracks(null) → URL 面包屑
    expect(container.read(titleProvider), '舔耳ONLY音轨');
  });

  test('普通 sourceId 搜索会清空 URL 面包屑状态', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    await container.read(uiServiceProvider).search(exampleUrl);
    expect(container.read(workTreePathProvider), isNotEmpty);

    final result = await container.read(uiServiceProvider).search('RJ010000');

    expect(result, 'RJ010000');
    expect(container.read(workTreePathProvider), isEmpty);
  });

  test('非法输入返回 null，不改变搜索状态', () async {
    final container = makeContainer();
    addTearDown(container.dispose);

    final result = await container.read(uiServiceProvider).search('abc');

    expect(result, isNull);
    expect(container.read(searchTextProvider), isNull);
  });
}
