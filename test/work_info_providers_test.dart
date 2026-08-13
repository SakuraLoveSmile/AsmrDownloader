import 'package:asmr_downloader/services/asmr_repo/providers/tracks_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/work_info_providers.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> fullWorkInfo() => {
        'title': '正式标题',
        'circle': {'name': '社团'},
        'vas': [
          {'name': 'CV1'}
        ],
        'tags': [
          {'i18n': {'zh-cn': {'name': '舔耳'}}}
        ],
        'mainCoverUrl': '',
        'release': '2026-06-09',
        'dl_count': 1,
      };

  /// 构造带 workTitle 的 tracks 树（与 asmr api 实际结构一致）
  List<dynamic> tracksWithWorkTitle(String title) => [
        {
          'type': 'folder',
          'title': 'RJ01619789',
          'children': [
            {'type': 'audio', 'title': 'x.wav', 'workTitle': title},
          ],
        },
      ];

  ProviderContainer makeContainer({
    Map<String, dynamic>? workInfo,
    List<dynamic>? tracks,
    List<String> treePath = const [],
  }) {
    final container = ProviderContainer(overrides: [
      sourceIdProvider.overrideWith((ref) => 'RJ01619789'),
      workInfoProvider.overrideWith((ref) async => workInfo),
      rawTracksProvider.overrideWith((ref) async => tracks),
      workTreePathProvider.overrideWith((ref) => treePath),
    ]);
    return container;
  }

  test('work info 成功时使用 work info 标题', () async {
    final container = makeContainer(workInfo: fullWorkInfo());
    addTearDown(container.dispose);

    await container.read(workInfoProvider.future);
    await container.read(rawTracksProvider.future);

    expect(container.read(titleProvider), '正式标题');
  });

  test('work info 失败时降级到 tracks 携带的 workTitle', () async {
    final container = makeContainer(
      workInfo: null,
      tracks: tracksWithWorkTitle('音轨标题'),
    );
    addTearDown(container.dispose);

    await container.read(workInfoProvider.future);
    await container.read(rawTracksProvider.future);

    expect(container.read(titleProvider), '音轨标题');
  });

  test('work info/tracks 都失败时降级到 URL 目录面包屑', () async {
    final container = makeContainer(
      workInfo: null,
      tracks: null,
      treePath: ['RJ01619789', '舔耳ONLY音轨'],
    );
    addTearDown(container.dispose);

    await container.read(workInfoProvider.future);
    await container.read(rawTracksProvider.future);

    expect(container.read(titleProvider), '舔耳ONLY音轨');
  });

  test('所有数据源都失败时保底 sourceId', () async {
    final container = makeContainer(workInfo: null, tracks: null);
    addTearDown(container.dispose);

    await container.read(workInfoProvider.future);
    await container.read(rawTracksProvider.future);

    expect(container.read(titleProvider), 'RJ01619789');
  });

  test('work info 标题为空字符串时继续降级', () async {
    final container = makeContainer(
      workInfo: {'title': ''},
      tracks: tracksWithWorkTitle('音轨标题'),
    );
    addTearDown(container.dispose);

    await container.read(workInfoProvider.future);
    await container.read(rawTracksProvider.future);

    expect(container.read(titleProvider), '音轨标题');
  });

  group('findWorkTitleInTracks', () {
    test('null 返回 null', () {
      expect(findWorkTitleInTracks(null), isNull);
    });

    test('空列表返回 null', () {
      expect(findWorkTitleInTracks([]), isNull);
    });

    test('递归查找嵌套节点的 workTitle', () {
      final found = findWorkTitleInTracks(tracksWithWorkTitle('嵌套标题'));
      expect(found, '嵌套标题');
    });

    test('workTitle 为空时继续深入', () {
      final tracks = [
        {
          'type': 'folder',
          'title': 'r',
          'children': [
            {'type': 'audio', 'title': 'a', 'workTitle': ''},
            {'type': 'text', 'title': 'b', 'workTitle': '真实标题'},
          ],
        },
      ];
      expect(findWorkTitleInTracks(tracks), '真实标题');
    });
  });
}
