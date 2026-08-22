import 'package:asmr_downloader/pages/downloader/search_result/tracks_view/components/download_progress/download_list_panel.dart';
import 'package:asmr_downloader/pages/downloader/search_result/tracks_view/components/download_progress/download_queue_panel.dart';
import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/download/download_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 下载中心顶部的持久任务面板。
///
/// 搜索结果会随 sourceId 切换而重建，下载状态则必须独立存在；因此把
/// 当前作品的逐文件进度和作品队列放到搜索区之外，下载中切换搜索也不会
/// 看不到正在下载的音声文件。
class DownloadActivityPanel extends ConsumerWidget {
  const DownloadActivityPanel({
    super.key,
    this.showEmpty = false,
    this.listMaxHeight = 280,
    this.queueMaxHeight = 180,
  });

  final bool showEmpty;
  final double listMaxHeight;
  final double queueMaxHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(dlStatusProvider);
    final segments = ref.watch(downloadSegmentsProvider);
    final currentSourceId = ref.watch(currentDownloadingSourceIdProvider);
    final lastSourceId = ref.watch(lastDownloadSourceIdProvider);
    final queue = ref.watch(downloadQueueProvider);

    final hasCurrentActivity = currentSourceId != null || segments.isNotEmpty;
    final hasActivity = hasCurrentActivity || queue.isNotEmpty;
    if (!hasActivity && status != DownloadStatus.downloading) {
      return showEmpty
          ? const _EmptyDownloadActivity()
          : const SizedBox.shrink();
    }

    final sourceId = currentSourceId ?? lastSourceId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasCurrentActivity)
            _CurrentDownloadCard(
              sourceId: sourceId,
              status: status,
              hasSegments: segments.isNotEmpty,
              listMaxHeight: listMaxHeight,
              onCancel: status == DownloadStatus.downloading
                  ? ref.read(downloadManagerProvider).cancelAllDownload
                  : null,
            ),
          if (queue.isNotEmpty)
            DownloadQueuePanel(
              tracksLPadding: 0,
              maxHeight: queueMaxHeight,
            ),
        ],
      ),
    );
  }
}

class _CurrentDownloadCard extends StatelessWidget {
  const _CurrentDownloadCard({
    required this.sourceId,
    required this.status,
    required this.hasSegments,
    required this.listMaxHeight,
    required this.onCancel,
  });

  final String? sourceId;
  final DownloadStatus status;
  final bool hasSegments;
  final double listMaxHeight;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = status == DownloadStatus.downloading;
    final title = active ? '正在下载' : '最近一次下载';
    final statusText = switch (status) {
      DownloadStatus.downloading => '下载中',
      DownloadStatus.completed => '已完成',
      DownloadStatus.failed => '有文件失败',
      DownloadStatus.canceled => '已取消',
      DownloadStatus.notStarted => '等待中',
    };
    final statusColor = switch (status) {
      DownloadStatus.downloading => scheme.primary,
      DownloadStatus.completed => Colors.green,
      DownloadStatus.failed => scheme.error,
      DownloadStatus.canceled => scheme.onSurfaceVariant,
      DownloadStatus.notStarted => scheme.onSurfaceVariant,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                active ? Icons.downloading_rounded : Icons.audio_file_rounded,
                size: 18,
                color: statusColor,
              ),
              const SizedBox(width: 7),
              Text(
                title,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (sourceId != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    sourceId!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (onCancel != null) ...[
                const SizedBox(width: 6),
                IconButton(
                  onPressed: onCancel,
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  tooltip: '取消下载',
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    foregroundColor: scheme.error,
                    padding: const EdgeInsets.all(4),
                    minimumSize: const Size(26, 26),
                  ),
                ),
              ],
            ],
          ),
          if (!hasSegments && active) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 4),
            const SizedBox(height: 6),
            Text(
              '正在准备音轨列表…',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 4),
          ] else if (hasSegments)
            DownloadListPanel(
              tracksLPadding: 0,
              initiallyExpanded: true,
              maxHeight: listMaxHeight,
            ),
        ],
      ),
    );
  }
}

class _EmptyDownloadActivity extends StatelessWidget {
  const _EmptyDownloadActivity();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.download_done_rounded,
            size: 42,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 12),
          Text(
            '暂无下载任务',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '开始搜索作品后，下载进度和队列会显示在这里',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
