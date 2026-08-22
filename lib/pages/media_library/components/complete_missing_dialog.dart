import 'package:asmr_downloader/pages/app_shell.dart';
import 'package:asmr_downloader/services/cache/media_library_settings.dart';
import 'package:asmr_downloader/services/tasks/background_task_service.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 将补全媒体库缺失项加入后台任务队列。
class CompleteMissingDialog extends ConsumerWidget {
  const CompleteMissingDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('补全缺失'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('将扫描已缓存的 workInfo，只请求缺少的 tracks 和封面。'),
            const SizedBox(height: 8),
            Text(
              '统一请求间隔：${formatMediaLibraryRequestInterval(ref.watch(mediaLibraryRequestIntervalProvider))}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              '任务会在后台逐条处理，关闭这个窗口或切换页面都不会中断。'
              '已有缓存不会重复请求。',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          onPressed: () {
            ref.read(backgroundTaskProvider.notifier).startCompleteMissing(
                  interval: ref.read(mediaLibraryRequestIntervalProvider),
                );
            Navigator.of(context).pop();
            ref.read(uiServiceProvider).showSnack(
                  '补全缺失已加入后台任务',
                  action: SnackBarAction(
                    label: '查看任务',
                    onPressed: () => ref
                        .read(currentPageProvider.notifier)
                        .state = AppPageIndex.backgroundTasks,
                  ),
                );
          },
          icon: const Icon(Icons.play_arrow_rounded, size: 17),
          label: const Text('加入后台任务'),
        ),
      ],
    );
  }
}
