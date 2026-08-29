import 'dart:typed_data';

import 'package:asmr_downloader/services/asmr_repo/asmr_api.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/api_providers.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/utils/source_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 记录搜索调用的 API 替身：search 返回预置结果并计数。
class _RecordingApi extends AsmrApi {
  final Map<String, dynamic>? searchResult;
  int searchCalls = 0;

  _RecordingApi(this.searchResult);

  @override
  Future<Map<String, dynamic>?> search({
    required String content,
    Map<String, dynamic>? params,
    int maxTry = 3,
  }) async {
    searchCalls++;
    return searchResult;
  }

  @override
  Future<Uint8List?> getCoverBytes(String url) async => null;
}

void main() {
  group('SourceId 单元', () {
    test('isPrefixed：RJ/VJ/BJ + 数字（忽略大小写）为真，纯数字/含字母为假', () {
      expect(SourceId.isPrefixed('RJ123456'), isTrue);
      expect(SourceId.isPrefixed('VJ01234567'), isTrue);
      expect(SourceId.isPrefixed('BJ123456'), isTrue);
      expect(SourceId.isPrefixed('rj123456'), isTrue);
      expect(SourceId.isPrefixed('vj123456'), isTrue);
      expect(SourceId.isPrefixed('123456'), isFalse);
      expect(SourceId.isPrefixed('RJ12a34'), isFalse);
      expect(SourceId.isPrefixed('XX123456'), isFalse);
    });

    test('normalize：统一大写，非法返回 null', () {
      expect(SourceId.normalize('vj01234567'), 'VJ01234567');
      expect(SourceId.normalize('  bj123456 '), 'BJ123456');
      expect(SourceId.normalize('RJ12a34'), isNull);
      expect(SourceId.normalize('123456'), isNull);
    });

    test('digits：提取数字段', () {
      expect(SourceId.digits('RJ01234567'), '01234567');
      expect(SourceId.digits('bj123456'), '123456');
    });
  });

  group('搜索 provider 统一 RJ/VJ/BJ 解析', () {
    test('VJ/BJ 前缀输入直查编号，不触发关键字搜索', () async {
      final api = _RecordingApi(null);
      final container = ProviderContainer(overrides: [
        asmrApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);

      for (final input in ['VJ01234567', 'bj123456', 'RJ123456']) {
        container.read(searchTextProvider.notifier).state = input;
        // 让 searchResultProvider 的 future 完成（若被触发）
        await container.read(searchResultProvider.future);
        expect(api.searchCalls, 0, reason: '$input 不应触发关键字搜索');
        expect(
          container.read(sourceIdProvider),
          input.trim().toUpperCase(),
          reason: '$input 应直查 sourceId',
        );
        expect(
          container.read(idProvider),
          SourceId.digits(input),
          reason: '$input 应直查数字 id',
        );
      }
    });

    test('纯数字/关键字输入仍走搜索路径', () async {
      final api = _RecordingApi({
        'works': [
          {'id': 42, 'source_id': 'VJ999999'}
        ],
      });
      final container = ProviderContainer(overrides: [
        asmrApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);

      container.read(searchTextProvider.notifier).state = '123456';
      final result = await container.read(searchResultProvider.future);
      expect(api.searchCalls, 1);
      expect(result, isNotNull);
      expect(container.read(idProvider), '42');
      expect(container.read(sourceIdProvider), 'VJ999999');
    });

    test('空搜索结果不抛异常，返回 null', () async {
      final api = _RecordingApi({'works': <Object>[]});
      final container = ProviderContainer(overrides: [
        asmrApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);

      container.read(searchTextProvider.notifier).state = '关键字';
      await container.read(searchResultProvider.future);
      expect(container.read(idProvider), isNull);
      expect(container.read(sourceIdProvider), isNull);
    });

    test('搜索结果缺 works 字段/结构异常时返回 null', () async {
      final api = _RecordingApi({'other': 1});
      final container = ProviderContainer(overrides: [
        asmrApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);

      container.read(searchTextProvider.notifier).state = '关键字';
      await container.read(searchResultProvider.future);
      expect(container.read(idProvider), isNull);
      expect(container.read(sourceIdProvider), isNull);
    });
  });
}
