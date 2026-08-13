import 'dart:convert';

import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('matchSourceIdFromDirName', () {
    test('识别 RJ/VJ/BJ 目录名并规范化大写', () {
      expect(matchSourceIdFromDirName('RJ12345678'), 'RJ12345678');
      expect(matchSourceIdFromDirName('rj12345678'), 'RJ12345678');
      expect(matchSourceIdFromDirName('VJ12345678'), 'VJ12345678');
      expect(matchSourceIdFromDirName('BJ123456'), 'BJ123456');
      expect(matchSourceIdFromDirName(' RJ12345678 '), 'RJ12345678');
    });

    test('非作品目录不识别（避免误判）', () {
      expect(matchSourceIdFromDirName('2024'), isNull); // 纯数字（年份）
      expect(matchSourceIdFromDirName('12345678'), isNull); // 纯数字
      expect(matchSourceIdFromDirName('音声资料'), isNull);
      expect(matchSourceIdFromDirName('RJ12345'), isNull); // 位数不足
      expect(matchSourceIdFromDirName('RJ12345678901'), isNull); // 超过 10 位
      expect(matchSourceIdFromDirName('RJ12345678_cover'), isNull); // 带后缀
      expect(matchSourceIdFromDirName('abcRJ12345678'), isNull); // 带前缀
      expect(matchSourceIdFromDirName(''), isNull);
    });
  });

  group('smartTruncate', () {
    test('短名原样返回', () {
      expect(smartTruncate('测试标题'), '测试标题');
      expect(smartTruncate('A' * 80), 'A' * 80);
    });

    test('长 ASCII 名截断到 maxChars 并加省略号', () {
      final r = smartTruncate('a' * 300, maxChars: 80);
      expect(r.runes.length, 81); // 80 + …
      expect(r, '${'a' * 80}…');
      expect(r.endsWith('…'), true);
    });

    test('长 CJK 名按字节上限回退（80 个 3 字节字符超 240 字节）', () {
      final r = smartTruncate('あ' * 100, maxChars: 80);
      // 79 * 3 + 3（…）= 240 字节刚好在限内
      expect(r, '${'あ' * 79}…');
      expect(r.runes.length, 80);
      expect(utf8.encode(r).length, 240);
    });

    test('emoji 长名受 UTF-8 字节上限保护', () {
      final r = smartTruncate('😀' * 100, maxChars: 80, maxUtf8Bytes: 240);
      expect(utf8.encode(r).length, lessThanOrEqualTo(240));
      expect(r.endsWith('…'), true);
      // 59 * 4 + 3 = 239 字节
      expect(r, '${'😀' * 59}…');
    });

    test('截断处残留分隔符被清理', () {
      // 'x - ' * 30 截断到 80 码点后尾部是 " - "，应被清理，不留 " - …"
      final r1 = smartTruncate('x - ' * 30, maxChars: 80);
      expect(r1, '${'x - ' * 19}x…');
      expect(r1.endsWith('…'), true);
      expect(r1.contains(' - …'), false);
      // 尾部标点被清理：截断后以分隔符结尾时去掉最后一个分隔符
      final r2 = smartTruncate('字、' * 50, maxChars: 80, maxUtf8Bytes: 300);
      expect(r2, '${'字、' * 39}字…');
      expect(r2.endsWith('、…'), false);
    });

    test('裁剪后为空返回空串（调用方兜底）', () {
      expect(smartTruncate(' - - - ' * 30, maxChars: 80), '');
    });

    test('不超字节上限但超字符数时仍截断', () {
      final r = smartTruncate('字' * 90, maxChars: 80); // 90*3=270 字节 > 240 也超
      expect(r.endsWith('…'), true);
      expect(r.runes.length, lessThanOrEqualTo(81));
    });
  });
}
