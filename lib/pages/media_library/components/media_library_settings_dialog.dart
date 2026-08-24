import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/cache/cache_library_providers.dart';
import 'package:asmr_downloader/services/cache/media_library_settings.dart';
import 'package:asmr_downloader/services/library/media_library_service.dart';
import 'package:asmr_downloader/services/library/work_library_status.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// 媒体库设置：管理扫描根目录和后台网络任务请求间隔。
class MediaLibrarySettingsDialog extends ConsumerWidget {
  const MediaLibrarySettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final roots = ref.watch(mediaLibraryRootsProvider);
    final interval = ref.watch(mediaLibraryRequestIntervalProvider);

    return AlertDialog(
      title: const Text('媒体库设置'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRootsSection(context, ref, roots),
              const SizedBox(height: 18),
              DropdownButtonFormField<Duration>(
                initialValue: interval,
                decoration: const InputDecoration(
                  labelText: '统一请求间隔',
                  helperText: '应用于主动缓存、一键补全等媒体库后台网络任务',
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
                '目录只扫描文件夹名中的 RJ/VJ/BJ 号，不读取音频、字幕或封面明细。'
                '目录暂时不可用时会保留上次记录，避免 NAS 未挂载时重复下载。',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
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

  Widget _buildRootsSection(
    BuildContext context,
    WidgetRef ref,
    List<String> roots,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_special_outlined,
                  size: 16, color: scheme.primary),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  '扫描目录',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton.icon(
                onPressed: () => _addRoot(context, ref),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('添加目录'),
              ),
            ],
          ),
          if (roots.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('尚未设置扫描目录'),
            )
          else
            ...roots.map(
              (root) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_outlined, size: 18),
                title: Text(
                  root,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: IconButton(
                  onPressed: () => _removeRoot(ref, root),
                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                  tooltip: '移除扫描目录',
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addRoot(BuildContext context, WidgetRef ref) async {
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择媒体库扫描目录（可选择已挂载的 SMB/NAS 目录）',
    );
    if (selected == null || selected.trim().isEmpty) return;

    final normalized = p.normalize(selected.trim());
    final roots = [...ref.read(mediaLibraryRootsProvider)];
    if (!roots.any((root) => p.equals(p.normalize(root), normalized))) {
      roots.add(normalized);
      _saveRoots(ref, roots);
      if (context.mounted) {
        ref.read(uiServiceProvider).showSnack('已添加媒体库扫描目录', context: context);
      }
    }
  }

  Future<void> _removeRoot(WidgetRef ref, String root) async {
    final roots = [...ref.read(mediaLibraryRootsProvider)]
      ..removeWhere((item) => p.equals(p.normalize(item), p.normalize(root)));
    await ref.read(mediaLibraryServiceProvider).removeRoot(root);
    _saveRoots(ref, roots);
  }

  void _saveRoots(WidgetRef ref, List<String> roots) {
    ref.read(mediaLibraryRootsProvider.notifier).state = roots;
    ref.read(configFileProvider).addOrUpdate({'mediaLibraryRoots': roots});
    ref.invalidate(cachedLibraryProvider);
    ref.invalidate(workLibraryStatusProvider);
  }
}
