import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DownloadButton extends ConsumerWidget {
  const DownloadButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(dlStatusProvider);
    final downloading = status == DownloadStatus.downloading;
    final failed = status == DownloadStatus.failed;

    // 下载中 → 红色「取消」；失败 → 「重试」；其余 → 「下载」
    final Color backgroundColor;
    final String label;
    final VoidCallback? onTap;
    if (downloading) {
      backgroundColor = Colors.redAccent;
      label = '取消';
      onTap = () => ref.read(downloadManagerProvider).cancelAllDownload();
    } else if (failed) {
      backgroundColor = Colors.orange;
      label = '重试';
      onTap = ref.read(downloadManagerProvider).run;
    } else {
      backgroundColor = Colors.pink[200]!;
      label = '下载';
      onTap = ref.read(downloadManagerProvider).run;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      decoration: ShapeDecoration(
        color: backgroundColor,
        shape: const StadiumBorder(),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          splashColor: Colors.pinkAccent.withValues(alpha: 0.3),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}
