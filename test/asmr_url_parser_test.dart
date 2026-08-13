import 'package:asmr_downloader/utils/asmr_url_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 用户调研示例：path 参数是 URL 编码的 JSON 面包屑
  // ["RJ01619789","舔耳ONLY音轨"]
  const exampleUrl =
      'https://asmr-200.com/work/RJ01619789?path=%5B%22RJ01619789%22,%22%E8%88%94%E8%80%B3ONLY%E9%9F%B3%E8%BD%A8%22%5D#work-tree';

  group('parseAsmrWorkUrl', () {
    test('解析示例 URL：提取 sourceId 与目录面包屑', () {
      final info = parseAsmrWorkUrl(exampleUrl);

      expect(info, isNotNull);
      expect(info!.sourceId, 'RJ01619789');
      expect(info.treePath, ['RJ01619789', '舔耳ONLY音轨']);
    });

    test('无 path 参数：面包屑为空，sourceId 仍可用', () {
      final info =
          parseAsmrWorkUrl('https://asmr-200.com/work/RJ01619789#work-tree');

      expect(info!.sourceId, 'RJ01619789');
      expect(info.treePath, isEmpty);
    });

    test('path 只有根节点', () {
      final info = parseAsmrWorkUrl(
          'https://asmr-200.com/work/RJ01619789?path=%5B%22RJ01619789%22%5D');

      expect(info!.treePath, ['RJ01619789']);
    });

    test('多级目录面包屑按顺序保留', () {
      final info = parseAsmrWorkUrl(
          'https://asmr-200.com/work/RJ01619789?path=%5B%22RJ01619789%22,%22mp3%22,%22b%22%5D');

      expect(info!.treePath, ['RJ01619789', 'mp3', 'b']);
    });

    test('主站 asmr.one 与小写 id', () {
      final info = parseAsmrWorkUrl('https://asmr.one/work/rj01000');

      expect(info!.sourceId, 'RJ01000');
    });

    test('api 前缀域名与 VJ id', () {
      final info = parseAsmrWorkUrl('https://api.asmr-100.com/work/VJ010000');

      expect(info!.sourceId, 'VJ010000');
    });

    test('path 参数非法 JSON 时容错：忽略面包屑', () {
      final info =
          parseAsmrWorkUrl('https://asmr-200.com/work/RJ01619789?path=notjson');

      expect(info!.sourceId, 'RJ01619789');
      expect(info.treePath, isEmpty);
    });

    test('path 不是数组时容错', () {
      final info =
          parseAsmrWorkUrl('https://asmr-200.com/work/RJ01619789?path=%7B%22a%22%3A1%7D');

      expect(info!.sourceId, 'RJ01619789');
      expect(info.treePath, isEmpty);
    });

    test('普通 sourceId 输入返回 null', () {
      expect(parseAsmrWorkUrl('RJ01619789'), isNull);
    });

    test('带前后空白的 URL 也能解析', () {
      final info = parseAsmrWorkUrl('  $exampleUrl  ');

      expect(info!.sourceId, 'RJ01619789');
    });

    test('非 asmr 站点 URL 返回 null', () {
      expect(parseAsmrWorkUrl('https://example.com/work/RJ01619789'), isNull);
    });
  });

  group('fallbackTitleFromTreePath', () {
    test('有子目录时取子目录名', () {
      expect(
        fallbackTitleFromTreePath(['RJ01619789', '舔耳ONLY音轨'], 'RJ01619789'),
        '舔耳ONLY音轨',
      );
    });

    test('多级子目录用 / 拼接', () {
      expect(
        fallbackTitleFromTreePath(['RJ01619789', 'mp3', 'b'], 'RJ01619789'),
        'mp3 / b',
      );
    });

    test('只有根节点时保底 sourceId', () {
      expect(fallbackTitleFromTreePath(['RJ01619789'], 'RJ01619789'), 'RJ01619789');
    });

    test('空面包屑保底 sourceId', () {
      expect(fallbackTitleFromTreePath([], 'RJ01619789'), 'RJ01619789');
    });
  });
}
