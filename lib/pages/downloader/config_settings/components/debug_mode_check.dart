import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/pages/components/labeled_checkbox.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Debug 模式开关：开启后把日志输出到应用数据目录的
/// `debug/asmr_downloader.log`，便于在 Windows 等平台排查问题。
class DebugModeCheck extends ConsumerWidget {
  const DebugModeCheck({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debugMode = ref.watch(debugModeProvider);
    return Tooltip(
      message: '开启后日志会写入应用数据目录 debug/asmr_downloader.log，'
          '方便 Windows 等平台排查问题',
      child: LabeledCheckbox(
        label: 'Debug 模式',
        value: debugMode,
        onChanged: ref.read(uiServiceProvider).onDebugModeChanged,
      ),
    );
  }
}
