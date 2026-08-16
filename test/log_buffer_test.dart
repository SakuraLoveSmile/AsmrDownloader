import 'package:asmr_downloader/utils/log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogEntry.format', () {
    test('格式化为 [MM-dd HH:mm:ss] LEVEL text', () {
      final e = LogEntry(
        time: DateTime(2026, 8, 16, 9, 5, 3),
        level: 'INFO',
        text: 'hello',
      );
      expect(e.format(), '[08-16 09:05:03] INFO hello');
    });

    test('多行文本原样保留', () {
      final e = LogEntry(
        time: DateTime(2026, 1, 2, 23, 59, 59),
        level: 'ERROR',
        text: 'failed\nerror: boom',
      );
      expect(e.format(), '[01-02 23:59:59] ERROR failed\nerror: boom');
    });
  });

  group('LogBuffer', () {
    test('add 追加并通知监听者', () {
      final buffer = LogBuffer();
      var notified = 0;
      buffer.addListener(() => notified++);
      buffer.add(LogEntry(
          time: DateTime.now(), level: 'INFO', text: 'a'));
      buffer.add(LogEntry(
          time: DateTime.now(), level: 'WARN', text: 'b'));
      expect(buffer.entries.map((e) => e.text), ['a', 'b']);
      expect(notified, 2);
    });

    test('超过上限时丢弃最旧条目', () {
      final buffer = LogBuffer();
      for (var i = 0; i < LogBuffer.maxEntries + 10; i++) {
        buffer.add(LogEntry(
            time: DateTime.now(), level: 'INFO', text: 'line $i'));
      }
      expect(buffer.entries.length, LogBuffer.maxEntries);
      expect(buffer.entries.first.text, 'line 10');
      expect(buffer.entries.last.text,
          'line ${LogBuffer.maxEntries + 9}');
    });

    test('clear 清空并通知；空缓冲清空不通知', () {
      final buffer = LogBuffer();
      var notified = 0;
      buffer.addListener(() => notified++);
      buffer.clear();
      expect(notified, 0);
      buffer.add(LogEntry(
          time: DateTime.now(), level: 'INFO', text: 'x'));
      buffer.clear();
      expect(buffer.entries, isEmpty);
      expect(notified, 2);
    });
  });

  group('Log 静态方法与缓冲联动', () {
    test('各级别日志进入缓冲且级别正确', () {
      final before = Log.buffer.entries.length;
      Log.trace('t');
      Log.debug('d');
      Log.info('i');
      Log.warning('w');
      Log.error('e', error: 'boom');
      Log.fatal('f');
      final added = Log.buffer.entries.skip(before).toList();
      expect(added.length, 6);
      expect(added.map((e) => e.level),
          ['TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL']);
      // error 附带 error 信息
      expect(added[4].text, contains('boom'));
    });
  });
}
