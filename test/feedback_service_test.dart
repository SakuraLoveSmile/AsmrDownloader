import 'dart:io';
import 'dart:typed_data';

import 'package:asmr_downloader/services/feedback/feedback_service.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late FeedbackService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('feedback_test_');
    service = FeedbackService();
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('保存反馈：写入截图与说明文件到时间戳目录', () async {
    final feedback = UserFeedback(
      text: '下载按钮点了没反应',
      screenshot: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
    );

    final dirPath = await service.save(
      feedback,
      appVersion: '0.14.0',
      rootDir: tempDir.path,
    );

    final dir = Directory(dirPath);
    expect(dir.existsSync(), isTrue);
    expect(dir.parent.path, p.join(tempDir.path, 'feedback'));

    final png = File(p.join(dir.path, 'screenshot.png'));
    expect(png.existsSync(), isTrue);
    expect(await png.readAsBytes(), feedback.screenshot);

    final txt = File(p.join(dir.path, 'feedback.txt'));
    expect(txt.existsSync(), isTrue);
    final content = await txt.readAsString();
    expect(content, contains('下载按钮点了没反应'));
    expect(content, contains('0.14.0'));
    expect(content, contains(FeedbackService.issuesUrl));
  });

  test('保存反馈：同一秒内多次提交不互相覆盖（时间戳含毫秒）', () async {
    UserFeedback fb(String text) =>
        UserFeedback(text: text, screenshot: Uint8List(0));

    final dir1 =
        await service.save(fb('a'), appVersion: '', rootDir: tempDir.path);
    final dir2 =
        await service.save(fb('b'), appVersion: '', rootDir: tempDir.path);

    expect(dir1, isNot(dir2));
    expect(
        File(p.join(dir1, 'feedback.txt')).readAsStringSync(), contains('a'));
    expect(
        File(p.join(dir2, 'feedback.txt')).readAsStringSync(), contains('b'));
  });
}
