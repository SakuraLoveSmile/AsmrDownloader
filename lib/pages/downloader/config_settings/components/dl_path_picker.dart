import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:asmr_downloader/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DownloadPathPicker extends ConsumerWidget {
  const DownloadPathPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dlPath = ref.watch(downloadPathProvider);
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: 150,
            maxWidth: (MediaQuery.sizeOf(context).width * 0.22)
                .clamp(180.0, 240.0)
                .toDouble(),
          ),
          child: TextField(
            enabled: false,
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              prefixIcon: const Icon(
                Icons.folder_rounded,
                size: 16,
                color: AppColors.folder,
              ),
              hintText: dlPath.isEmpty ? '选择下载路径' : dlPath,
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: ref.read(uiServiceProvider).pickDlPath,
          icon: const Icon(Icons.folder_open_rounded, size: 17),
          tooltip: '选择下载路径',
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            shape: const CircleBorder(),
            backgroundColor: scheme.surfaceContainerHigh.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(width: 2),
        IconButton(
          onPressed: ref.read(uiServiceProvider).openFolder,
          icon: const Icon(Icons.launch_rounded, size: 16),
          tooltip: '在访达/资源管理器中打开',
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            shape: const CircleBorder(),
            backgroundColor: scheme.surfaceContainerHigh.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }
}
