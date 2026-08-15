import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 下载速度与剩余时间（仅在下载中且有速度时显示）
class DownloadSpeed extends ConsumerWidget {
  const DownloadSpeed({super.key});

  static String _formatEta(Duration eta) {
    if (eta <= Duration.zero) return '';
    final totalSeconds = eta.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) return '$hours 小时 $minutes 分';
    if (minutes > 0) return '$minutes 分 $seconds 秒';
    return '$seconds 秒';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(downloadSpeedProvider);
    final eta = ref.watch(downloadEtaProvider);
    if (speed <= 0) return const SizedBox.shrink();

    final etaText = _formatEta(eta);
    final text = etaText.isEmpty
        ? '${getSizeString(speed.round())}/s'
        : '${getSizeString(speed.round())}/s · 剩余 $etaText';
    return Text(
      text,
      style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}
