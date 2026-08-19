import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/download/download_queue.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
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

    if (downloading) {
      // 下载中渲染两个按钮：主色「加入队列」+ 红色「取消」
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _EnqueueButton(scheme: scheme),
          const SizedBox(width: 8),
          _CancelButton(scheme: scheme),
        ],
      );
    }

    // 失败 → 橙色「重试」；其余 → 主色「下载」
    final Color backgroundColor;
    final String label;
    final VoidCallback? onTap;
    if (failed) {
      backgroundColor = AppColors.warningSolid;
      label = '重试';
      onTap = ref.read(downloadManagerProvider).run;
    } else {
      backgroundColor = scheme.primary;
      label = '下载';
      onTap = ref.read(downloadManagerProvider).run;
    }

    return _PillButton(
      backgroundColor: backgroundColor,
      onColor: scheme.onPrimary,
      label: label,
      onTap: onTap,
    );
  }
}

/// 下载中的「加入队列」按钮：把当前搜索的作品 sourceId 加入下载队列。
/// sourceId 为 null、等于当前正在下载的作品、或已在队列中时禁用并说明原因。
class _EnqueueButton extends ConsumerWidget {
  const _EnqueueButton({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourceId = ref.watch(sourceIdProvider);
    final currentDl = ref.watch(currentDownloadingSourceIdProvider);
    final queue = ref.watch(downloadQueueProvider);

    String? tooltip;
    bool disabled = false;
    if (sourceId == null) {
      disabled = true;
      tooltip = '当前无有效作品可加入队列';
    } else if (sourceId == currentDl) {
      disabled = true;
      tooltip = '该作品正在下载中';
    } else if (queue.contains(sourceId)) {
      disabled = true;
      tooltip = '该作品已在队列中';
    }

    return _PillButton(
      backgroundColor: scheme.primary,
      onColor: scheme.onPrimary,
      label: '加入队列',
      onTap: disabled
          ? null
          : () async {
              final added =
                  await ref.read(downloadQueueProvider.notifier).add(sourceId!);
              if (added) {
                final remaining = ref.read(downloadQueueProvider).length;
                ref
                    .read(uiServiceProvider)
                    .showSnack('已加入下载队列（剩余 $remaining 个）');
              }
            },
      tooltip: tooltip,
    );
  }
}

/// 下载中的红色「取消」按钮：终止当前下载并停止队列循环。
class _CancelButton extends ConsumerWidget {
  const _CancelButton({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _PillButton(
      backgroundColor: scheme.error,
      onColor: scheme.onPrimary,
      label: '取消',
      onTap: () => ref.read(downloadManagerProvider).cancelAllDownload(),
    );
  }
}

/// 统一的胶囊按钮外观，与原有下载按钮保持一致。
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.backgroundColor,
    required this.onColor,
    required this.label,
    required this.onTap,
    this.tooltip,
  });

  final Color backgroundColor;
  final Color onColor;
  final String label;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      decoration: ShapeDecoration(
        color: onTap == null
            ? backgroundColor.withValues(alpha: 0.4)
            : backgroundColor,
        shape: const StadiumBorder(),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          splashColor: onColor.withValues(alpha: 0.3),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(color: onColor, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
