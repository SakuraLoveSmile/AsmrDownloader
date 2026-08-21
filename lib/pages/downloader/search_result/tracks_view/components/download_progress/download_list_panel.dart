import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/pages/components/middle_ellipsis_text.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 下载列表面板：在进度行与音轨树之间逐文件列出下载详情。
/// 无分段数据（未开始/新搜索清空）时整体不渲染。
class DownloadListPanel extends ConsumerStatefulWidget {
  const DownloadListPanel({
    super.key,
    required this.tracksLPadding,
    this.initiallyExpanded = false,
  });

  final double tracksLPadding;
  final bool initiallyExpanded;

  @override
  ConsumerState<DownloadListPanel> createState() => _DownloadListPanelState();
}

class _DownloadListPanelState extends ConsumerState<DownloadListPanel> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // 面板可能在下载状态已经切换后才首次出现在下载中心（例如用户
    // 搜索结果正在加载时），此时没有状态边沿可供 ref.listen 捕获。
    _expanded = widget.initiallyExpanded ||
        ref.read(dlStatusProvider) == DownloadStatus.downloading;
  }

  @override
  Widget build(BuildContext context) {
    final segments = ref.watch(downloadSegmentsProvider);
    if (segments.isEmpty) return const SizedBox.shrink();

    // 下载开始时自动展开（新一轮 run() 会将状态置为 downloading）
    ref.listen<DownloadStatus>(dlStatusProvider, (previous, next) {
      if (next == DownloadStatus.downloading && !_expanded) {
        setState(() => _expanded = true);
      }
    });

    final completed = ref.watch(currentDlNoProvider);
    final total = ref.watch(totalTaskCntProvider);

    return Padding(
      padding: EdgeInsets.only(left: widget.tracksLPadding, bottom: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Header(
            expanded: _expanded,
            completed: completed,
            total: total,
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            firstChild: const SizedBox.shrink(),
            secondChild: _ListBody(segments: segments),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.expanded,
    required this.completed,
    required this.total,
    required this.onTap,
  });

  final bool expanded;
  final int completed;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 20,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              '下载列表',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$completed / $total',
              style: TextStyle(
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListBody extends StatelessWidget {
  const _ListBody({required this.segments});

  final List<DownloadSegment> segments;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 280),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: segments.length,
        separatorBuilder: (_, __) => const SizedBox(height: 2),
        itemBuilder: (_, index) => _DownloadListRow(segment: segments[index]),
      ),
    );
  }
}

class _DownloadListRow extends StatelessWidget {
  const _DownloadListRow({required this.segment});

  final DownloadSegment segment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDownloading = segment.status == DownloadStatus.downloading;
    final isFailed = segment.status == DownloadStatus.failed;

    final (icon, iconColor) = _statusIcon(segment.status, scheme);

    final downloadedBytes = (segment.fraction * segment.size).round();
    final sizeText =
        '${getSizeString(downloadedBytes)} / ${getSizeString(segment.size)}';
    final rightText = isDownloading && segment.speed > 0
        ? '$sizeText · ${getSizeString(segment.speed.round())}/s'
        : sizeText;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: ellipsisInMiddle(
                    segment.title,
                    textStyle: TextStyle(
                      height: 1.0,
                      fontSize: 13,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: segment.fraction,
                  minHeight: 4,
                  backgroundColor: scheme.surfaceContainerHighest,
                  color: isFailed ? scheme.error : scheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            rightText,
            style: TextStyle(
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color) _statusIcon(DownloadStatus status, ColorScheme scheme) {
    switch (status) {
      case DownloadStatus.notStarted:
        return (Icons.schedule, scheme.onSurfaceVariant);
      case DownloadStatus.downloading:
        return (Icons.downloading, scheme.primary);
      case DownloadStatus.completed:
        return (Icons.check_circle, Colors.green);
      case DownloadStatus.failed:
        return (Icons.error, scheme.error);
      case DownloadStatus.canceled:
        return (Icons.stop_circle, scheme.onSurfaceVariant);
    }
  }
}
