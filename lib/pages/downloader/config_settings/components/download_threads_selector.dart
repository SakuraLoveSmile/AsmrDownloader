import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 单文件多线程下载的连接数选择器。
class DownloadThreadsSelector extends ConsumerWidget {
  const DownloadThreadsSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threads = ref.watch(downloadThreadsProvider);
    final value = downloadThreadOptions.contains(threads) ? threads : 4;
    return Tooltip(
      message: '单文件分段并发下载的连接数（每段至少 1 MiB）。'
          '服务器不支持 Range 时自动回退单线程',
      child: Padding(
        padding: const EdgeInsets.only(left: 20.0),
        child: Row(
          children: [
            const Text('下载线程'),
            SizedBox(
              child: DropdownButton<int>(
                value: value,
                focusColor: Colors.transparent,
                items: downloadThreadOptions.map((int option) {
                  return DropdownMenuItem<int>(
                    value: option,
                    child: Text(option == 1 ? '单线程' : '$option 线程'),
                  );
                }).toList(),
                onChanged: ref.read(uiServiceProvider).onDownloadThreadsChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
