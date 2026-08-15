import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 文件级并行下载数选择器。
///
/// 并行数只控制「同时下载几个文件」；单文件内仍由 [downloadThreadsProvider]
/// 控制分段线程数。并行时总连接数会被限制在 [maxTotalDownloadConnections] 以内。
class ParallelDownloadsSelector extends ConsumerWidget {
  const ParallelDownloadsSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parallel = ref.watch(parallelDownloadCountProvider);
    final value = parallelDownloadOptions.contains(parallel) ? parallel : 2;
    return Tooltip(
      message: '同时下载的文件数。并行时会自动压低单文件线程，'
          '确保总连接数不超过 $maxTotalDownloadConnections',
      child: Padding(
        padding: const EdgeInsets.only(left: 20.0),
        child: Row(
          children: [
            const Text('并行文件数'),
            const SizedBox(width: 6),
            DropdownMenu<int>(
              initialSelection: value,
              dropdownMenuEntries: parallelDownloadOptions
                  .map((option) => DropdownMenuEntry<int>(
                      value: option,
                      label: option == 1 ? '单文件' : '$option 文件'))
                  .toList(),
              onSelected:
                  ref.read(uiServiceProvider).onParallelDownloadCountChanged,
            ),
          ],
        ),
      ),
    );
  }
}
