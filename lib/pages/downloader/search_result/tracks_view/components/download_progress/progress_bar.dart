import 'package:asmr_downloader/pages/components/middle_ellipsis_text.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProgressBar extends ConsumerWidget {
  const ProgressBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final process = ref.watch(processProvider);
    final activeFileNames = ref.watch(activeFileNamesProvider);
    final displayText = switch (activeFileNames.length) {
      0 => '',
      1 => activeFileNames.first,
      2 => activeFileNames.join('、'),
      _ =>
        '${activeFileNames.take(2).join('、')} 等 ${activeFileNames.length} 个文件',
    };
    return Expanded(
      child: Stack(children: [
        LinearProgressIndicator(
          minHeight: 30,
          borderRadius: BorderRadius.circular(10),
          value: process,
        ),
        Positioned.fill(
          left: 10,
          right: 10,
          bottom: 1,
          child: Row(children: ellipsisInMiddle(displayText)),
        ),
      ]),
    );
  }
}
