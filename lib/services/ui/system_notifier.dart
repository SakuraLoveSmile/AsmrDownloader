import 'dart:io';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// 系统桌面通知服务：在 macOS 与 Windows 上发送原生任务完成通知。
class SystemNotifier {
  SystemNotifier(this.ref, {ProcessRunner? runner})
      : _runner = runner ?? Process.run;

  final Ref ref;
  final ProcessRunner _runner;

  /// 发送系统通知（根据配置开关决定是否执行，且全链路静默降级）。
  Future<void> notify(String title, String body) async {
    final enabled = ref.read(notifyOnCompleteProvider);
    if (!enabled) return;

    try {
      if (Platform.isMacOS) {
        // AppleScript 转义：反斜杠与双引号
        final escapedTitle =
            title.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
        final escapedBody = body.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
        final script =
            'display notification "$escapedBody" with title "$escapedTitle"';
        await _runner('osascript', ['-e', script]);
      } else if (Platform.isWindows) {
        // Windows PowerShell WinRT Toast 脚本
        final escapedTitle = title.replaceAll("'", "''").replaceAll('"', '`"');
        final escapedBody = body.replaceAll("'", "''").replaceAll('"', '`"');
        final psScript = '''
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > \$null
\$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
\$xml = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]::New()
\$xml.LoadXml(\$template.GetXml())
\$textNodes = \$xml.GetElementsByTagName("text")
\$textNodes.Item(0).AppendChild(\$xml.CreateTextNode("$escapedTitle")) > \$null
\$textNodes.Item(1).AppendChild(\$xml.CreateTextNode("$escapedBody")) > \$null
\$toast = [Windows.UI.Notifications.ToastNotification]::New(\$xml)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("ASMR Downloader").Show(\$toast)
''';
        await _runner(
          'powershell',
          ['-NoProfile', '-NonInteractive', '-Command', psScript],
        );
      }
    } catch (e) {
      Log.warning('system notification failed: $e');
    }
  }
}

final systemNotifierProvider = Provider<SystemNotifier>((ref) {
  return SystemNotifier(ref);
});
