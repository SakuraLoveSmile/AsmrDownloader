import 'package:asmr_downloader/services/asmr_repo/asmr_api.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/api_providers.dart';
import 'package:asmr_downloader/services/cache/batch_cache_service.dart';
import 'package:asmr_downloader/services/cache/cache_database.dart';
import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:asmr_downloader/services/cache/cache_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 可编程假 API：按页返回预设 works，getWorkInfo 按数字 id 返回预设 workInfo，
/// 可配置返回 null / 抛异常 / 搜索失败。
class FakeAsmrApi extends AsmrApi {
  FakeAsmrApi({Map<int, List<Map<String, dynamic>>>? searchPages})
      : searchPages = searchPages ?? {};

  /// page -> works 列表
  final Map<int, List<Map<String, dynamic>>> searchPages;
  final List<String> searchContents = [];
  final List<int> searchPagesCalled = [];
  final List<String> workInfoCalls = [];

  /// getWorkInfo 返回 null 的 id 集合（模拟 API 返回失败）
  final Set<String> nullWorkInfoIds = {};

  /// getWorkInfo 抛异常的 id 集合（模拟网络异常）
  final Set<String> throwingWorkInfoIds = {};

  /// search 抛异常（模拟搜索页请求失败）
  bool searchThrows = false;

  /// 搜索响应里的 pagination.totalCount（默认按请求过的最大页补算）
  int? totalCount;

  @override
  Future<Map<String, dynamic>?> search({
    required String content,
    Map<String, dynamic>? params,
    int maxTry = 3,
  }) async {
    if (searchThrows) throw Exception('search failed');
    searchContents.add(content);
    final page = (params?['page'] as int?) ?? 1;
    searchPagesCalled.add(page);
    final works = searchPages[page] ?? [];
    return {
      'works': works,
      'pagination': {
        'currentPage': page,
        'pageSize': params?['pageSize'] ?? 30,
        'totalCount': totalCount ?? works.length,
      },
    };
  }

  @override
  Future<Map<String, dynamic>?> getWorkInfo(String id) async {
    workInfoCalls.add(id);
    if (throwingWorkInfoIds.contains(id)) throw Exception('network error');
    if (nullWorkInfoIds.contains(id)) return null;
    return {
      'id': id,
      'title': '作品 $id',
      'circle': {'name': '测试社团'},
    };
  }
}

void main() {
  /// 构造搜索结果中的单个作品（与 asmr api 结构一致）
  Map<String, dynamic> work(int n) => {'id': '$n', 'source_id': 'RJ$n'};

  /// 带 circle / vas 字段的作品（circle / va 维度降级过滤时需要）
  Map<String, dynamic> workWith(
    int n, {
    String? circle,
    List<String>? vas,
  }) =>
      {
        'id': '$n',
        'source_id': 'RJ$n',
        if (circle != null) 'name': circle,
        if (circle != null)
          'circle': {'name': circle},
        if (vas != null) 'vas': [for (final v in vas) {'name': v}],
      };

  ProviderContainer makeContainer(CacheService cache, AsmrApi api) {
    final container = ProviderContainer(overrides: [
      cacheServiceProvider.overrideWith((ref) => cache),
      asmrApiProvider.overrideWith((ref) => api),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  (CacheService, FakeAsmrApi, BatchCacheService) setup(
    FakeAsmrApi api,
  ) {
    final db = CacheDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final cache = CacheService(db);
    final container = makeContainer(cache, api);
    final service = container.read(batchCacheServiceProvider);
    return (cache, api, service);
  }

  test('分页搜索全部作品并逐个缓存', () async {
    final api = FakeAsmrApi(searchPages: {
      1: List.generate(30, (i) => work(i + 1)),
      2: [work(31), work(32), work(33)],
    });
    final (cache, _, service) = setup(api);
    final progresses = <BatchCacheProgress>[];

    final result = await service.batchCache(
      BatchCacheDimension.tag,
      '舔耳',
      onProgress: progresses.add,
      isCancelled: () => false,
    );

    expect(result.cached, 33);
    expect(result.skipped, 0);
    expect(result.failed, 0);
    expect(result.cancelled, false);
    // 第一页满 30 条继续翻页，第二页不足 30 条停止
    expect(api.searchPagesCalled, [1, 2]);
    expect(api.searchContents, ['\$tag:舔耳\$', '\$tag:舔耳\$']); // 每页一次
    expect(api.workInfoCalls, List.generate(33, (i) => '${i + 1}'));
    expect(await cache.getCacheCount(), 33);
    expect(progresses, hasLength(33));
  });

  test('已缓存的作品自动跳过且不请求 API', () async {
    final api = FakeAsmrApi(searchPages: {
      1: [work(1), work(2), work(3)],
    });
    final (cache, _, service) = setup(api);
    await cache.saveWorkInfo('RJ2', {'title': '已缓存'});

    final result = await service.batchCache(
      BatchCacheDimension.tag,
      '舔耳',
      onProgress: (_) {},
      isCancelled: () => false,
    );

    expect(result.cached, 2);
    expect(result.skipped, 1);
    expect(result.failed, 0);
    expect(api.workInfoCalls, ['1', '3']); // 跳过 RJ2
    expect((await cache.getWorkInfo('RJ2'))?['title'], '已缓存'); // 未被覆盖
  });

  test('取消后停止（当前作品完成后）', () async {
    final api = FakeAsmrApi(searchPages: {
      1: [work(1), work(2), work(3), work(4)],
    });
    final (cache, _, service) = setup(api);
    var cancel = false;

    final result = await service.batchCache(
      BatchCacheDimension.tag,
      '舔耳',
      onProgress: (_) => cancel = true, // 第一个作品完成后请求取消
      isCancelled: () => cancel,
    );

    expect(result.cancelled, true);
    expect(result.cached, 1);
    expect(result.skipped, 0);
    expect(result.failed, 0);
    expect(api.workInfoCalls, ['1']); // 后续作品未处理
    expect(await cache.getCacheCount(), 1); // 已缓存条目保留
  });

  test('getWorkInfo 失败计入失败数并继续后续作品', () async {
    final api = FakeAsmrApi(searchPages: {
      1: [work(1), work(2), work(3)],
    });
    api
      ..nullWorkInfoIds.add('2')
      ..throwingWorkInfoIds.add('3');
    final (cache, _, service) = setup(api);

    final result = await service.batchCache(
      BatchCacheDimension.tag,
      '舔耳',
      onProgress: (_) {},
      isCancelled: () => false,
    );

    expect(result.cached, 1);
    expect(result.failed, 2);
    expect(result.skipped, 0);
    expect(api.workInfoCalls, ['1', '2', '3']); // 失败不中断流程
    expect(await cache.getCacheCount(), 1);
  });

  test('circle / va 维度降级为通用搜索并按名称精确过滤', () async {
    final api = FakeAsmrApi(searchPages: {
      // 第 1 页：混合社团与近名作品
      1: [
        workWith(1, circle: '糖果屋'),
        workWith(2, circle: '糖果工房'), // circle 名包含目标，命中
        workWith(3, circle: '別のサークル'), // 不命中，应被过滤
        workWith(4, vas: ['柚木つばめ']), // va 命中
        workWith(5, vas: ['别的CV']),
        work(6), // 无 circle/vas 字段，不命中
      ],
    });
    final (_, _, service) = setup(api);

    // circle 维度：内容为关键词本身，循环到 name 精确匹配的
    await service.batchCache(
      BatchCacheDimension.circle,
      '糖果',
      onProgress: (_) {},
      isCancelled: () => false,
    );
    expect(api.searchContents, ['糖果']); // 通用搜索，不再用 $circle:$
    expect(api.workInfoCalls, ['1', '2']); // 仅命中 circle 名含「糖果」的
    api.workInfoCalls.clear();

    await service.batchCache(
      BatchCacheDimension.va,
      '柚木',
      onProgress: (_) {},
      isCancelled: () => false,
    );
    expect(api.searchContents, ['糖果', '柚木']); // va 维度同样走通用搜索
    expect(api.workInfoCalls, ['4']); // 仅命中 vas 含「柚木」的
  });

  test('circle / va 维度所有作品均不命中时缓存 0', () async {
    final api = FakeAsmrApi(searchPages: {
      1: [workWith(1, circle: '无关社团'), workWith(2, vas: ['无关CV'])],
    });
    final (_, _, service) = setup(api);

    final result = await service.batchCache(
      BatchCacheDimension.circle,
      '完全不存在',
      onProgress: (_) {},
      isCancelled: () => false,
    );

    expect(result.cached, 0);
    expect(api.workInfoCalls, isEmpty);
  });

  test('搜索返回空/失败（重试耗尽返回 null）时干净停止', () async {
    final api = FakeAsmrApi(); // 无搜索结果页
    final (cache, _, service) = setup(api);

    final result = await service.batchCache(
      BatchCacheDimension.tag,
      '舔耳',
      onProgress: (_) {},
      isCancelled: () => false,
    );

    expect(result.cached, 0);
    expect(result.skipped, 0);
    expect(result.failed, 0);
    expect(result.cancelled, false);
    expect(api.searchPagesCalled, [1]);
    expect(api.workInfoCalls, isEmpty);
    expect(await cache.getCacheCount(), 0);
  });

  test('source_id 为空的作品跳过且不计入', () async {
    final api = FakeAsmrApi(searchPages: {
      1: [
        work(1),
        {'id': '9', 'source_id': ''}, // 无 source_id，无法作为缓存键
        work(2),
      ],
    });
    final (cache, _, service) = setup(api);

    final result = await service.batchCache(
      BatchCacheDimension.tag,
      '舔耳',
      onProgress: (_) {},
      isCancelled: () => false,
    );

    expect(result.cached, 2);
    expect(result.failed, 0);
    expect(api.workInfoCalls, ['1', '2']); // 空 source_id 不请求 API
    expect(await cache.getCacheCount(), 2);
  });

  test('搜索请求异常向上传播（由调用方处理）', () async {
    final api = FakeAsmrApi()..searchThrows = true;
    final (_, _, service) = setup(api);

    await expectLater(
      service.batchCache(
        BatchCacheDimension.tag,
        '舔耳',
        onProgress: (_) {},
        isCancelled: () => false,
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('进度带 pagination.totalCount，tag 标记为精确', () async {
    final api = FakeAsmrApi(searchPages: {
      1: [work(1), work(2)],
    })..totalCount = 42;
    final (_, _, service) = setup(api);
    final progresses = <BatchCacheProgress>[];

    await service.batchCache(
      BatchCacheDimension.tag,
      '舔耳',
      onProgress: progresses.add,
      isCancelled: () => false,
    );

    // 首个进度即带上 total，且 tag 维度不是近似
    expect(progresses.first.total, 42);
    expect(progresses.first.totalApprox, false);
  });

  test('circle 维度 total 标记为近似值', () async {
    final api = FakeAsmrApi(searchPages: {
      1: [workWith(1, circle: '糖果屋')],
    })..totalCount = 99;
    final (_, _, service) = setup(api);
    BatchCacheProgress? last;

    await service.batchCache(
      BatchCacheDimension.circle,
      '糖果',
      onProgress: (p) => last = p,
      isCancelled: () => false,
    );

    // circle 维度的 total 是服务端原始 totalCount（含无关条目，故为近似）
    expect(last?.total, 99);
    expect(last?.totalApprox, true);
  });

  test('runInterval 批量期间修改全局限速，结束后还原默认', () async {
    final api = FakeAsmrApi(searchPages: {
      1: [work(1)],
    });
    final (_, _, service) = setup(api);
    final limiter = service.ref.read(rateLimiterProvider);
    final defaultInterval = limiter.minInterval;

    await service.batchCache(
      BatchCacheDimension.tag,
      '舔耳',
      runInterval: const Duration(milliseconds: 50),
      onProgress: (_) {},
      isCancelled: () => false,
    );

    // 结束后还原为用户使用前的默认值
    expect(limiter.minInterval, defaultInterval);
  });
}
