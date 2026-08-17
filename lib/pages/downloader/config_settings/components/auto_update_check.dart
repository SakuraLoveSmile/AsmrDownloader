import 'package:asmr_downloader/pages/components/labeled_checkbox.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:asmr_downloader/services/update/update_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 自动检查更新开关：启动时自动检查 GitHub Release 是否有新版本。
class AutoUpdateCheck extends ConsumerWidget {
  const AutoUpdateCheck({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoCheck = ref.watch(autoCheckUpdateProvider);
    return Tooltip(
      message: '启动时自动检查 GitHub Release 新版本，发现后弹窗提示',
      child: LabeledCheckbox(
        label: '自动检查更新',
        value: autoCheck,
        onChanged: ref.read(uiServiceProvider).onAutoUpdateCheckChanged,
      ),
    );
  }
}
