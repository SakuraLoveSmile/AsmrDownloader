import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/download/download_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 下载队列面板：作品级队列展示与管理。
/// 仅当队列非空时渲染。每行展示 sourceId 与删除按钮，
/// 底部提供「清空队列」，非下载中时额外显示「继续下载」。
class DownloadQueuePanel extends ConsumerWidget {
  const DownloadQueuePanel({super.key, required this.tracksLPadding});

  final double tracksLPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(downloadQueueProvider);
    if (queue.isEmpty) return const SizedBox.shrink();

    final downloading =
        ref.watch(dlStatusProvider) == DownloadStatus.downloading;

    return Padding(
      padding: EdgeInsets.only(left: tracksLPadding, bottom: 8.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(count: queue.length),
            const SizedBox(height: 4),
            for (final sourceId in queue)
              _QueueRow(
                sourceId: sourceId,
                isDownloading: downloading,
                onRemove: () => ref
                    .read(downloadQueueProvider.notifier)
                    .remove(sourceId),
              ),
            const SizedBox(height: 4),
            _Footer(
              downloading: downloading,
              onClear: () => ref.read(downloadQueueProvider.notifier).clear(),
              onStartFromQueue: () =>
                  ref.read(downloadManagerProvider).startFromQueue(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(Icons.queue, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          '下载队列',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 12,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: color,
          ),
        ),
      ],
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.sourceId,
    required this.isDownloading,
    required this.onRemove,
  });

  final String sourceId;
  final bool isDownloading;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.audio_file, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              sourceId,
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 18),
            tooltip: '从队列移除',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.downloading,
    required this.onClear,
    required this.onStartFromQueue,
  });

  final bool downloading;
  final VoidCallback onClear;
  final VoidCallback onStartFromQueue;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TextButton.icon(
          onPressed: onClear,
          icon: const Icon(Icons.delete_sweep, size: 16),
          label: const Text('清空队列'),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        if (!downloading) ...[
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onStartFromQueue,
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('继续下载'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
        const Spacer(),
      ],
    );
  }
}
