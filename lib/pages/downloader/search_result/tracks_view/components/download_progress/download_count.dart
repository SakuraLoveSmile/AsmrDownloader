import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DownloadCount extends ConsumerWidget {
  const DownloadCount({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // currentDlNoProvider 在并行下载下表示「已完成文件数」
    final currentDl = ref.watch(currentDlNoProvider);
    final total = ref.watch(totalTaskCntProvider);
    final activeCnt = ref.watch(activeFileNamesProvider).length;
    // 下载中补充展示并行文件数，与分段进度条呼应
    final text = activeCnt > 0
        ? '$currentDl / $total · 下载中 $activeCnt'
        : '$currentDl / $total';
    return Text(
      text,
      style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
    );
  }
}
