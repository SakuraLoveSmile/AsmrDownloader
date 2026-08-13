import 'dart:io';

import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 下载注册表管理对话框：
/// 列出注册表条目（RJ 号 + 标题 + 目录存在状态 + 整理时间），
/// 支持单个删除、一键清理缺失条目。
class WorksIndexDialog extends ConsumerStatefulWidget {
  const WorksIndexDialog({super.key});

  @override
  ConsumerState<WorksIndexDialog> createState() => _WorksIndexDialogState();
}

class _WorksIndexDialogState extends ConsumerState<WorksIndexDialog> {
  List<WorkEntry>? _entries;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final entries = await ref.read(worksIndexProvider).list();
      entries.sort((a, b) => a.sourceId.compareTo(b.sourceId));
      if (mounted) setState(() => _entries = entries);
    } catch (e) {
      if (mounted) setState(() => _error = '读取注册表失败: $e');
    }
  }

  Future<void> _cleanMissing() async {
    final cleaned = await ref.read(worksIndexProvider).cleanMissing();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已清理 $cleaned 条缺失条目')));
    await _reload();
  }

  Future<void> _remove(WorkEntry entry) async {
    await ref.read(worksIndexProvider).remove(entry.sourceId);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final missingCount = entries
        ?.where((e) => !Directory(e.sourceDir).existsSync())
        .length ??
        0;

    return AlertDialog(
      title: const Text('下载注册表'),
      content: SizedBox(
        width: 480,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('条目：${entries?.length ?? 0}，缺失：$missingCount',
                    style: Theme.of(context).textTheme.bodySmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: missingCount == 0 ? null : _cleanMissing,
                  icon: const Icon(Icons.cleaning_services, size: 16),
                  label: Text('清理缺失 ($missingCount)'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _buildList(context, entries),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
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

  Widget _buildList(BuildContext context, List<WorkEntry>? entries) {
    if (_error != null) return const SizedBox.shrink();
    if (entries == null) return const Center(child: CircularProgressIndicator());
    if (entries.isEmpty) return const Center(child: Text('暂无条目'));

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView.builder(
        itemCount: entries.length,
        itemBuilder: (context, i) {
          final entry = entries[i];
          final dirExists = Directory(entry.sourceDir).existsSync();
          return ListTile(
            dense: true,
            leading: Icon(
              dirExists ? Icons.folder : Icons.folder_off,
              size: 18,
              color: dirExists ? Colors.white70 : Colors.redAccent,
            ),
            title: Text(entry.sourceId,
                style: Theme.of(context).textTheme.bodySmall),
            subtitle: Text(
              '${entry.title}\n整理：${entry.organizedAt ?? '未整理'}',
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => _remove(entry),
              tooltip: '删除条目',
            ),
          );
        },
      ),
    );
  }
}
