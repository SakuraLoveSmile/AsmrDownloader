import 'package:asmr_downloader/services/asmr_repo/asmr_api.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/api_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/work_info_providers.dart';
import 'package:asmr_downloader/services/cache/cache_database.dart';
import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:asmr_downloader/services/cache/cache_service.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

class _FakeApi extends AsmrApi {
  final Map<String, Map<String, dynamic>> works;
  _FakeApi(this.works);

  @override
  Future<Map<String, dynamic>?> getWorkInfo(String id) async => works[id];

  @override
  Future<List<dynamic>?> getTracks(String id) async => const [];
}

void main() {
  late Directory testBase;
  late WorksIndex index;

  setUp(() {
    testBase = Directory.systemTemp.createTempSync('circle_name_provider_test');
    index = WorksIndex(filePath: p.join(testBase.path, 'works_index.json'));
  });

  tearDown(() => testBase.deleteSync(recursive: true));

  ProviderContainer makeContainer(Map<String, Map<String, dynamic>> works,
      {Map<String, dynamic>? workInfoOverride}) {
    final cacheDb = CacheDatabase.forTesting(NativeDatabase.memory());
    addTearDown(cacheDb.close);
    return ProviderContainer(overrides: [
      worksIndexProvider.overrideWith((ref) => index),
      asmrApiProvider.overrideWith((ref) => _FakeApi(works)),
      cacheServiceProvider.overrideWith((ref) => CacheService(cacheDb)),
      if (workInfoOverride != null)
        workInfoProvider.overrideWith((ref) async => workInfoOverride),
    ]);
  }

  group('circleNameProvider', () {
    test('原版作品直接返回当前社团名', () async {
      final container = makeContainer({}, workInfoOverride: {
        'title': '原作',
        'circle': {'name': 'B-bishop'},
        'translation_info': {'is_original': true},
        'other_language_editions_in_db': <Object>[],
      });
      addTearDown(container.dispose);

      final name = await container.read(circleNameProvider.future);
      expect(name, 'B-bishop');
    });

    test('汉化版跟踪到原版取真实社团名', () async {
      // 原版 RJ01617295（id 1617295）已可由 API 返回
      final works = <String, Map<String, dynamic>>{
        '1617295': {
          'title': 'オナサポ20連ガチャ！2',
          'circle': {'name': 'B-bishop'},
          'translation_info': {'is_original': true},
        },
      };
      final container = makeContainer(works, workInfoOverride: {
        'title': '【简体中文版】自慰辅助20连抽卡！2',
        'circle': {'name': '把你涅普涅普掉'},
        'translation_info': {
          'is_original': false,
          'original_workno': 'RJ01617295',
        },
        'other_language_editions_in_db': [
          {'id': 1617295, 'source_id': 'RJ01617295', 'is_original': true},
        ],
      });
      addTearDown(container.dispose);

      final name = await container.read(circleNameProvider.future);
      expect(name, 'B-bishop');
    });

    test('原版信息获取失败时 fallback 汉化组名', () async {
      // API 无原版数据
      final container = makeContainer({}, workInfoOverride: {
        'title': '【简体中文版】测试',
        'circle': {'name': '汉化组'},
        'translation_info': {
          'is_original': false,
          'original_workno': 'RJ01617295',
        },
        'other_language_editions_in_db': [
          {'id': 1617295, 'source_id': 'RJ01617295', 'is_original': true},
        ],
      });
      addTearDown(container.dispose);

      final name = await container.read(circleNameProvider.future);
      expect(name, '汉化组');
    });

    test('无 translation_info 时 fallback 当前社团名', () async {
      final container = makeContainer({}, workInfoOverride: {
        'title': '普通作品',
        'circle': {'name': '社团RJ00001'},
      });
      addTearDown(container.dispose);

      final name = await container.read(circleNameProvider.future);
      expect(name, '社团RJ00001');
    });
  });
}
