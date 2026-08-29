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

    // 已在待下载队列中的作品不能再次直接下载，否则会在队列消费后
    // 重复下载同一个作品。
    final sourceId = ref.watch(sourceIdProvider);
    final queue = ref.watch(downloadQueueProvider);
    if (sourceId != null && queue.any((item) => item.sourceId == sourceId)) {
      return _PillButton(
        backgroundColor: scheme.surfaceContainerHighest,
        onColor: scheme.onSurfaceVariant,
        label: '已排队',
        onTap: null,
        tooltip: '该作品已在下载队列中，请从队列继续下载',
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
class _EnqueueButton extends ConsumerStatefulWidget {
  const _EnqueueButton({required this.scheme});

  final ColorScheme scheme;

  @override
  ConsumerState<_EnqueueButton> createState() => _EnqueueButtonState();
}

class _EnqueueButtonState extends ConsumerState<_EnqueueButton> {
  bool _adding = false;

  @override
  Widget build(BuildContext context) {
    final sourceId = ref.watch(sourceIdProvider);
    final currentDl = ref.watch(currentDownloadingSourceIdProvider);
    final queue = ref.watch(downloadQueueProvider);
    final rootFolder = ref.watch(rootFolderProvider);
    final tracksReady = rootFolder != null && rootFolder.id == sourceId;

    String? tooltip;
    var disabled = _adding;
    if (sourceId == null) {
      disabled = true;
      tooltip = '当前无有效作品可加入队列';
    } else if (sourceId == currentDl) {
      disabled = true;
      tooltip = '该作品正在下载中';
    } else if (!tracksReady) {
      disabled = true;
      tooltip = '音轨仍在加载，请稍候';
    } else if (queue.any((item) => item.sourceId == sourceId)) {
      disabled = true;
      tooltip = '该作品已在队列中';
    }

    return _PillButton(
      backgroundColor: widget.scheme.primary,
      onColor: widget.scheme.onPrimary,
      label: '加入队列',
      onTap: disabled ? null : () => _enqueue(sourceId!),
      tooltip: tooltip,
    );
  }

  Future<void> _enqueue(String sourceId) async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      final rootFolder = ref.read(rootFolderProvider);
      if (rootFolder == null || rootFolder.id != sourceId) {
        ref.read(uiServiceProvider).showSnack('音轨仍在加载，请稍候再加入队列');
        return;
      }
      final selectedIds = selectedFileIds(rootFolder);
      final bool added;
      try {
        added = await ref.read(downloadQueueProvider.notifier).add(
              sourceId,
              selectedTrackIds: selectedIds,
            );
      } catch (e) {
        // 持久层写入失败：明确告知未入队，不让用户误以为已成功
        if (!mounted) return;
        ref.read(uiServiceProvider).showSnack('加入队列失败（队列保存出错）：$e');
        return;
      }
      if (!mounted) return;

      if (added) {
        final remaining = ref.read(downloadQueueProvider).length;
        final selectionText = selectedIds.isEmpty
            ? '未勾选音轨，将只下载封面'
            : '已记录 ${selectedIds.length} 个音轨';
        ref
            .read(uiServiceProvider)
            .showSnack('已加入下载队列（$selectionText，剩余 $remaining 个）');
      } else if (ref
          .read(downloadQueueProvider)
          .any((item) => item.sourceId == sourceId)) {
        ref.read(uiServiceProvider).showSnack('该作品已在下载队列中');
      } else {
        ref.read(uiServiceProvider).showSnack('加入队列失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
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

/// 统一的 Apple 胶囊按钮外观。
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
    final disabled = onTap == null;
    final button = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: ShapeDecoration(
        color: disabled
            ? backgroundColor.withValues(alpha: 0.35)
            : backgroundColor,
        shape: const StadiumBorder(),
        shadows: disabled
            ? null
            : [
                BoxShadow(
                  color: backgroundColor.withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                )
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          splashColor: onColor.withValues(alpha: 0.2),
          highlightColor: onColor.withValues(alpha: 0.1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: disabled ? onColor.withValues(alpha: 0.5) : onColor,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                letterSpacing: -0.1,
              ),
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
