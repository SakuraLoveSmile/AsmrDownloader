import 'package:asmr_downloader/services/cache/media_library_settings.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 媒体库统一设置：所有媒体库后台网络任务共用这里的请求间隔。
class MediaLibrarySettingsDialog extends ConsumerWidget {
  const MediaLibrarySettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final interval = ref.watch(mediaLibraryRequestIntervalProvider);

    return AlertDialog(
      title: const Text('媒体库设置'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<Duration>(
              initialValue: interval,
              decoration: const InputDecoration(
                labelText: '统一请求间隔',
                helperText: '应用于主动缓存、补全缺失等媒体库后台网络任务',
              ),
              items: [
                for (final option in mediaLibraryRequestIntervalOptions)
                  DropdownMenuItem<Duration>(
                    value: option,
                    child: Text(formatMediaLibraryRequestInterval(option)),
                  ),
              ],
              onChanged: (value) => ref
                  .read(uiServiceProvider)
                  .onMediaLibraryRequestIntervalChanged(value),
            ),
            const SizedBox(height: 12),
            Text(
              '设置会自动保存。已经加入队列的任务保持加入时的间隔，之后的新任务使用最新设置。',
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
      ],
    );
  }
}
