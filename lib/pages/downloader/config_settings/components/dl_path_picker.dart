import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DownloadPathPicker extends ConsumerWidget {
  const DownloadPathPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dlPath = ref.watch(downloadPathProvider);
    return SizedBox(
      height: 50.0,
      child: Padding(
        padding: const EdgeInsets.only(left: 20.0),
        child: Row(
          children: [
            SizedBox(
              width: 250,
              child: TextField(
                enabled: false,
                decoration: InputDecoration(
                  hintText: dlPath.isEmpty ? '选择下载路径' : dlPath,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 5.0),
              child: IconButton(
                onPressed: ref.read(uiServiceProvider).pickDlPath,
                icon: const Icon(Icons.folder),
                tooltip: '选择下载路径',
                visualDensity: VisualDensity.compact,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 5.0),
              child: IconButton(
                onPressed: ref.read(uiServiceProvider).openFolder,
                icon: const Icon(Icons.folder_open),
                tooltip: '打开下载目录',
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
