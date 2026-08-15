import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/pages/components/labeled_checkbox.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 下载完成后自动整理到 Navidrome
class AutoOrganizeCheck extends ConsumerWidget {
  const AutoOrganizeCheck({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoOrganize = ref.watch(autoOrganizeProvider);
    return Tooltip(
      message: '下载完成后自动整理到 Navidrome 媒体库（整理路径未设置时自动整理会跳过）',
      child: Padding(
        padding: const EdgeInsets.only(left: 20.0),
        child: LabeledCheckbox(
          label: '开启整理',
          value: autoOrganize,
          onChanged: ref.read(uiServiceProvider).onAutoOrganizeChanged,
        ),
      ),
    );
  }
}
