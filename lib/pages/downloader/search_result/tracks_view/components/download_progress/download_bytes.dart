import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 已下载 / 总数据量（总大小未知时不显示）
class DownloadBytes extends ConsumerWidget {
  const DownloadBytes({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloaded = ref.watch(downloadedBytesProvider);
    final total = ref.watch(totalBytesProvider);
    if (total <= 0) return const SizedBox.shrink();

    return Text(
      '${getSizeString(downloaded)} / ${getSizeString(total)}',
      style: TextStyle(
          fontSize: 12,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}
