import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/batch_organize_dialog.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/works_index_dialog.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 批量整理按钮：打开批量整理对话框（含进度/取消/开关）。
class OrganizeAllButton extends ConsumerWidget {
  const OrganizeAllButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloading =
        ref.watch(dlStatusProvider) == DownloadStatus.downloading;

    return SizedBox(
      child: Padding(
        padding: const EdgeInsets.only(left: 20.0),
        child: OutlinedButton(
          onPressed: downloading
              ? null
              : () => showDialog(
                    context: context,
                    builder: (_) => const BatchOrganizeDialog(),
                  ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.white24),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            foregroundColor: Colors.white70,
            disabledForegroundColor: Colors.white24,
          ),
          child: const Text('整理全部'),
        ),
      ),
    );
  }
}

/// 下载注册表管理按钮：手动清理注册表条目。
class WorksIndexButton extends ConsumerWidget {
  const WorksIndexButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      child: Padding(
        padding: const EdgeInsets.only(left: 20.0),
        child: OutlinedButton(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => const WorksIndexDialog(),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.white24),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            foregroundColor: Colors.white70,
            disabledForegroundColor: Colors.white24,
          ),
          child: const Text('注册表'),
        ),
      ),
    );
  }
}
