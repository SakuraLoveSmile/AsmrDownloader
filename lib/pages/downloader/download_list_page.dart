import 'package:asmr_downloader/pages/app_shell.dart';
import 'package:asmr_downloader/pages/downloader/download_activity_panel.dart';
import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/download/download_queue.dart';
import 'package:asmr_downloader/ui/page_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 独立下载列表页：集中展示当前/最近一次下载的逐文件进度和作品队列。
class DownloadListPage extends ConsumerWidget {
  const DownloadListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(dlStatusProvider);
    final currentSourceId = ref.watch(currentDownloadingSourceIdProvider);
    final lastSourceId = ref.watch(lastDownloadSourceIdProvider);
    final segments = ref.watch(downloadSegmentsProvider);
    final queue = ref.watch(downloadQueueProvider);
    final scheme = Theme.of(context).colorScheme;

    final statusText =
        currentSourceId != null || status == DownloadStatus.downloading
            ? '下载中'
            : queue.isNotEmpty
                ? '队列中 ${queue.length} 个作品'
                : segments.isNotEmpty || lastSourceId != null
                    ? '最近一次下载'
                    : '暂无活动任务';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          icon: Icons.playlist_play_rounded,
          title: '下载列表',
          subtitle: statusText,
          actions: [
            TextButton.icon(
              onPressed: () => ref.read(currentPageProvider.notifier).state =
                  AppPageIndex.downloader,
              icon: const Icon(Icons.search_rounded, size: 16),
              label: const Text('开始新下载'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          ],
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 10, bottom: 20),
            child: DownloadActivityPanel(
              showEmpty: true,
              listMaxHeight: 560,
              queueMaxHeight: 280,
            ),
          ),
        ),
      ],
    );
  }
}
