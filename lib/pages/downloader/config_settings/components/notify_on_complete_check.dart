import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/pages/components/labeled_checkbox.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 任务完成通知开关：下载、整理、AI 字幕及后台任务完成时发送系统桌面通知。
class NotifyOnCompleteCheck extends ConsumerWidget {
  const NotifyOnCompleteCheck({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notify = ref.watch(notifyOnCompleteProvider);
    return Tooltip(
      message: '任务（下载、整理、AI 字幕及后台任务）完成时发送系统桌面通知',
      child: LabeledCheckbox(
        label: '任务完成通知',
        value: notify,
        onChanged: ref.read(uiServiceProvider).onNotifyOnCompleteChanged,
      ),
    );
  }
}
