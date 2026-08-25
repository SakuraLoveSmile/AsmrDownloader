import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/pages/update/update_dialog.dart';
import 'package:asmr_downloader/services/update/update_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 发现新版本时的常驻提醒横幅：跨「下载/作品库/媒体库」三页显示，
/// 比标题栏红点更醒目。用户点「稍后」按版本关闭，出现更高版本时自动恢复。
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = ref.watch(shouldShowUpdateBannerProvider);
    if (!show) return const SizedBox.shrink();
    final info = ref.watch(latestUpdateProvider).valueOrNull;
    if (info == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerHighest,
      child: InkWell(
        onTap: () => showUpdateDialog(context),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: scheme.primary, width: 3),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.system_update_alt, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '发现新版本 ${info.tagName}，点击查看更新内容',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium!
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _dismiss(ref, info.tagName),
                child: const Text('稍后'),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: () => showUpdateDialog(context),
                icon: const Icon(Icons.download_outlined, size: 16),
                label: const Text('立即更新'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 按版本关闭横幅：持久化到配置，出现更高版本时自动恢复。
  Future<void> _dismiss(WidgetRef ref, String tagName) async {
    ref.read(dismissedUpdateVersionProvider.notifier).state = tagName;
    await ref.read(configFileProvider).addOrUpdate({
      'dismissedUpdateVersion': tagName,
    });
  }
}
