import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/pages/library/tools/batch_organize_dialog.dart';
import 'package:asmr_downloader/pages/library/tools/works_index_dialog.dart';
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

    return OutlinedButton(
      key: const ValueKey('onboarding-organize-all'),
      onPressed: downloading
          ? null
          : () => showDialog(
                context: context,
                builder: (_) => const BatchOrganizeDialog(),
              ),
      child: const Text('整理全部'),
    );
  }
}

/// 下载注册表管理按钮：手动清理注册表条目。
class WorksIndexButton extends ConsumerWidget {
  const WorksIndexButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton(
      onPressed: () => showDialog(
        context: context,
        builder: (_) => const WorksIndexDialog(),
      ),
      child: const Text('注册表'),
    );
  }
}
