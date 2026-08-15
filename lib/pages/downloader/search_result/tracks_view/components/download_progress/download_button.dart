import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DownloadButton extends ConsumerWidget {
  const DownloadButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final status = ref.watch(dlStatusProvider);
    final downloading = status == DownloadStatus.downloading;
    final failed = status == DownloadStatus.failed;

    // 下载中 → 红色「取消」；失败 → 橙色「重试」；其余 → 主色「下载」
    final Color backgroundColor;
    final String label;
    final VoidCallback? onTap;
    if (downloading) {
      backgroundColor = scheme.error;
      label = '取消';
      onTap = () => ref.read(downloadManagerProvider).cancelAllDownload();
    } else if (failed) {
      backgroundColor = AppColors.warningSolid;
      label = '重试';
      onTap = ref.read(downloadManagerProvider).run;
    } else {
      backgroundColor = scheme.primary;
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
          splashColor: scheme.onPrimary.withValues(alpha: 0.3),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                  color: scheme.onPrimary, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}
