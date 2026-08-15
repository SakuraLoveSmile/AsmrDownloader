import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DownloadCount extends ConsumerWidget {
  const DownloadCount({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appWidth = MediaQuery.of(context).size.width;
    // currentDlNoProvider 在并行下载下表示「已完成文件数」
    final currentDl = ref.watch(currentDlNoProvider);
    final total = ref.watch(totalTaskCntProvider);
    return SizedBox(
      width: appWidth * 0.07,
      child: Center(child: Text('$currentDl / $total')),
    );
  }
}
