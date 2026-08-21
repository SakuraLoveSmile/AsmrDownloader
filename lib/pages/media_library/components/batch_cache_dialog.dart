import 'package:asmr_downloader/pages/app_shell.dart';
import 'package:asmr_downloader/services/cache/batch_cache_service.dart';
import 'package:asmr_downloader/services/cache/media_library_settings.dart';
import 'package:asmr_downloader/services/tasks/background_task_service.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 配置主动缓存并将其加入后台任务队列。
class BatchCacheDialog extends ConsumerStatefulWidget {
  const BatchCacheDialog({super.key});

  @override
  ConsumerState<BatchCacheDialog> createState() => _BatchCacheDialogState();
}

class _BatchCacheDialogState extends ConsumerState<BatchCacheDialog> {
  BatchCacheDimension _dimension = BatchCacheDimension.tag;
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _start() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    ref.read(backgroundTaskProvider.notifier).startBatchCache(
          dimension: _dimension,
          name: name,
          interval: ref.read(mediaLibraryRequestIntervalProvider),
        );
    Navigator.of(context).pop();
    ref.read(uiServiceProvider).showSnack(
          '主动缓存已加入后台任务',
          action: SnackBarAction(
            label: '查看任务',
            onPressed: () => ref.read(currentPageProvider.notifier).state = 3,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('主动缓存'),
      content: SizedBox(width: 480, child: _buildContent(context)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _nameController,
          builder: (context, value, _) => FilledButton.icon(
            onPressed: value.text.trim().isEmpty ? null : _start,
            icon: const Icon(Icons.play_arrow_rounded, size: 17),
            label: const Text('加入后台任务'),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<BatchCacheDimension>(
          initialValue: _dimension,
          decoration: const InputDecoration(labelText: '搜索维度'),
          items: const [
            DropdownMenuItem(
              value: BatchCacheDimension.tag,
              child: Text('按标签'),
            ),
            DropdownMenuItem(
              value: BatchCacheDimension.circle,
              child: Text('按社团'),
            ),
            DropdownMenuItem(
              value: BatchCacheDimension.va,
              child: Text('按 CV'),
            ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _dimension = value);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: '名称',
            hintText: '输入标签 / 社团 / CV 名称',
          ),
          onSubmitted: (_) => _start(),
        ),
        const SizedBox(height: 12),
        InputDecorator(
          decoration: const InputDecoration(
            labelText: '统一请求间隔',
            helperText: '可在媒体库工具栏的「媒体库设置」中修改',
          ),
          child: Text(
            formatMediaLibraryRequestInterval(
              ref.watch(mediaLibraryRequestIntervalProvider),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '任务会在后台逐个获取 workInfo，已缓存作品自动跳过。'
          '关闭这个窗口或切换页面都不会中断；多个后台任务会按顺序执行。',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// 主动缓存按钮：打开主动缓存配置窗口。
class BatchCacheButton extends ConsumerWidget {
  const BatchCacheButton({super.key, this.onClosed});

  final VoidCallback? onClosed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton(
      onPressed: () async {
        await showDialog<void>(
          context: context,
          builder: (_) => const BatchCacheDialog(),
        );
        onClosed?.call();
      },
      child: const Text('主动缓存'),
    );
  }
}
