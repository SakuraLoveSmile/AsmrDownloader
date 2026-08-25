import 'package:asmr_downloader/utils/vtt_to_lrc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('vttToLrc', () {
    test('标准样例（真实 asmr.one VTT）', () {
      const vtt = 'WEBVTT\n\n'
          '1\n'
          '00:00:00.900 --> 00:00:05.000\n'
          '深入舔耳特化型智能性爱人偶 即将启动\n\n'
          '2\n'
          '00:00:09.108 --> 00:00:17.458\n'
          '初次见面您好 我是智能性爱人偶「001」\n';

      final lrc = vttToLrc(vtt);

      expect(lrc, isNotNull);
      expect(
          lrc,
          '[00:00.90]深入舔耳特化型智能性爱人偶 即将启动\n'
          '[00:09.10]初次见面您好 我是智能性爱人偶「001」');
    });

    test('小时超过 1 小时：分钟数累加', () {
      const vtt = 'WEBVTT\n\n'
          '00:00:00.000 --> 00:00:01.000\n'
          '开始\n\n'
          '01:05:03.500 --> 01:05:05.000\n'
          '一小时零五分\n';

      final lrc = vttToLrc(vtt);

      expect(lrc, '[00:00.00]开始\n[65:03.50]一小时零五分');
    });

    test('多行 cue 文本合并为一行', () {
      const vtt = 'WEBVTT\n\n'
          '00:00:01.000 --> 00:00:02.000\n'
          '第一行\n'
          '第二行\n\n'
          '00:00:03.000 --> 00:00:04.000\n'
          '单独\n';

      final lrc = vttToLrc(vtt);

      expect(lrc, '[00:01.00]第一行 第二行\n[00:03.00]单独');
    });

    test('NOTE 块与空文本 cue 被跳过', () {
      const vtt = 'WEBVTT\n\n'
          'NOTE 这是一段注释\n可以多行\n\n'
          '00:00:00.000 --> 00:00:01.000\n'
          '有效内容\n\n'
          '00:00:02.000 --> 00:00:03.000\n\n'
          '00:00:03.000 --> 00:00:04.000\n'
          '  \n';

      final lrc = vttToLrc(vtt);

      expect(lrc, '[00:00.00]有效内容');
    });

    test('无小时格式 MM:SS.mmm 与逗号毫秒分隔符', () {
      const vtt = 'WEBVTT\n\n'
          '01:23.456 --> 01:25.000\n'
          '无小时测试\n\n'
          '00:02:00,500 --> 00:02:03,000\n'
          '逗号毫秒\n';

      final lrc = vttToLrc(vtt);

      expect(lrc, '[01:23.45]无小时测试\n[02:00.50]逗号毫秒');
    });

    test('毫秒一位/两位按小数秒处理', () {
      const vtt = 'WEBVTT\n\n'
          '00:00:00.9 --> 00:00:01.0\n'
          '一位\n\n'
          '00:00:02.99 --> 00:00:03.0\n'
          '两位\n';

      final lrc = vttToLrc(vtt);

      expect(lrc, '[00:00.90]一位\n[00:02.99]两位');
    });

    test('无有效 cue 返回 null', () {
      expect(vttToLrc('WEBVTT\n\nNOTE nothing here\n'), isNull);
      expect(vttToLrc(''), isNull);
      expect(vttToLrc('   \n\n随便写点啥\n'), isNull);
    });

    test('CRLF 行尾与无 WEBVTT 头', () {
      const vtt = '00:00:00.000 --> 00:00:01.000\r\n'
          '没有头也能转\r\n';

      expect(vttToLrc(vtt), '[00:00.00]没有头也能转');
    });

    test('cue 编号为任意文本也能跳过', () {
      const vtt = 'WEBVTT\n\n'
          'cue-one\n'
          '00:00:00.000 --> 00:00:01.000\n'
          '文本\n';

      expect(vttToLrc(vtt), '[00:00.00]文本');
    });
  });
}
