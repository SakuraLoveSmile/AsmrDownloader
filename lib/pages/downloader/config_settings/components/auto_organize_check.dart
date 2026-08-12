import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 下载完成后自动整理到 Navidrome
class AutoOrganizeCheck extends ConsumerWidget {
  const AutoOrganizeCheck({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoOrganize = ref.watch(autoOrganizeProvider);
    return SizedBox(
      child: Padding(
        padding: const EdgeInsets.only(left: 20.0),
        child: Row(
          children: [
            const Text('开启整理'),
            Checkbox(
              value: autoOrganize,
              onChanged: ref.read(uiServiceProvider).onAutoOrganizeChanged,
            ),
          ],
        ),
      ),
    );
  }
}
