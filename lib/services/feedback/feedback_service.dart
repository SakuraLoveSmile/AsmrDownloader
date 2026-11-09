import 'dart:io';

import 'package:asmr_downloader/services/update/update_service.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:feedback/feedback.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

/// 用户反馈落盘服务：把 feedback 组件提交的「标注截图 + 文字说明」写入
/// <应用数据目录>/feedback/<时间戳>/，随后由用户作为 GitHub Issue 附件提交。
class FeedbackService {
  /// 仓库 Issues 页（与 [UpdateService.repo] 同源），写入 feedback.txt
  /// 指引用户提交，避免散落第二份仓库地址常量。
  static final issuesUrl = 'https://github.com/${UpdateService.repo}/issues';

  /// 保存一条用户反馈，返回写入的目录路径。
  ///
  /// 产物：`screenshot.png`（用户标注过的页面截图）与
  /// `feedback.txt`（文字说明 + 版本/平台/时间，便于 triage）。
  /// [rootDir] 仅供测试注入，默认写到应用数据目录下的 feedback/。
  Future<String> save(
    UserFeedback feedback, {
    required String appVersion,
    String? rootDir,
  }) async {
    final stamp = DateFormat('yyyyMMdd_HHmmssSSS').format(DateTime.now());
    final dir =
        Directory(p.join(rootDir ?? getAppDataDir(), 'feedback', stamp));
    await dir.create(recursive: true);

    await File(p.join(dir.path, 'screenshot.png'))
        .writeAsBytes(feedback.screenshot, flush: true);

    final info = StringBuffer()
      ..writeln(feedback.text.trim())
      ..writeln()
      ..writeln('---')
      ..writeln('版本：$appVersion')
      ..writeln('平台：${Platform.operatingSystem} '
          '${Platform.operatingSystemVersion}')
      ..writeln('时间：${DateTime.now().toIso8601String()}')
      ..writeln('提交入口：$issuesUrl（把本目录的 screenshot.png 作为附件上传）');
    await File(p.join(dir.path, 'feedback.txt'))
        .writeAsString(info.toString(), flush: true);

    Log.info('feedback saved: ${dir.path}');
    return dir.path;
  }
}
