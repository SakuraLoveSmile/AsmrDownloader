import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 缓存管理对话框：
/// 显示缓存条目数（workInfo / tracks / 封面）与数据库文件路径，
/// 支持清空缓存、导出 .db 文件、导入 .db 文件。
class CacheDialog extends ConsumerStatefulWidget {
  const CacheDialog({super.key});

  @override
  ConsumerState<CacheDialog> createState() => _CacheDialogState();
}

class _CacheDialogState extends ConsumerState<CacheDialog> {
  int? _workInfoCount;
  int? _tracksCount;
  int? _coverCount;
  String? _dbPath;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final cache = ref.read(cacheServiceProvider);
      final counts = await Future.wait([
        cache.getCacheCount(),
        cache.getTracksCount(),
        cache.getCoverCount(),
      ]);
      if (!mounted) return;
      setState(() {
        _workInfoCount = counts[0];
        _tracksCount = counts[1];
        _coverCount = counts[2];
        _dbPath = cache.dbPath;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '读取缓存信息失败: $e');
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空缓存'),
        content:
            const Text('将删除全部 workInfo / tracks / 封面缓存，下次访问需重新请求 API。确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(cacheServiceProvider).clearCache();
      if (!mounted) return;
      ref.read(uiServiceProvider).showSnack(context: context, '缓存已清空');
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ref.read(uiServiceProvider).showSnack(context: context, '清空缓存失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportCache() async {
    final targetPath = await FilePicker.platform.saveFile(
      dialogTitle: '导出缓存数据库',
      fileName: 'asmr_cache.db',
      type: FileType.custom,
      allowedExtensions: ['db'],
    );
    if (targetPath == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(cacheServiceProvider).exportTo(targetPath);
      if (!mounted) return;
      ref
          .read(uiServiceProvider)
          .showSnack(context: context, '缓存已导出到 $targetPath');
    } catch (e) {
      if (!mounted) return;
      ref.read(uiServiceProvider).showSnack(context: context, '导出失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importCache() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '导入缓存数据库',
      type: FileType.custom,
      allowedExtensions: ['db'],
    );
    final sourcePath = result?.files.single.path;
    if (sourcePath == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入缓存'),
        content: Text('将用 $sourcePath 覆盖当前缓存数据库，确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(cacheServiceProvider).importFrom(sourcePath);
      if (!mounted) return;
      ref.read(uiServiceProvider).showSnack(context: context, '缓存导入成功');
    } catch (e) {
      if (!mounted) return;
      ref.read(uiServiceProvider).showSnack(context: context, '导入失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('缓存管理'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('workInfo 条目：${_workInfoCount ?? '…'}',
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text('tracks 条目：${_tracksCount ?? '…'}',
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text('封面条目：${_coverCount ?? '…'}',
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Text('数据库文件：', style: theme.textTheme.bodySmall),
            SelectableText(_dbPath ?? '…',
                style: theme.textTheme.bodySmall!.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _clearCache,
                  icon: const Icon(Icons.delete_sweep, size: 16),
                  label: const Text('清空缓存'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _exportCache,
                  icon: const Icon(Icons.upload_file, size: 16),
                  label: const Text('导出缓存'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _importCache,
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('导入缓存'),
                ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
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

/// 缓存管理按钮：打开缓存管理对话框。
class CacheButton extends ConsumerWidget {
  const CacheButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton(
      onPressed: () => showDialog(
        context: context,
        builder: (_) => const CacheDialog(),
      ),
      child: const Text('缓存'),
    );
  }
}
