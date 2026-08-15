import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/pages/library/tools/works_index_dialog.dart';
import 'package:asmr_downloader/services/library/library_providers.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/organize_service.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 批量整理对话框：
/// - 开始前：选择「仅整理未整理的」开关，显示注册表条目数/缺失数
/// - 运行中：进度条 + 当前作品 + 结果列表 + 取消
/// - 完成：汇总 + 结果列表 + 清理缺失 + 管理注册表
class BatchOrganizeDialog extends ConsumerStatefulWidget {
  const BatchOrganizeDialog({super.key});

  @override
  ConsumerState<BatchOrganizeDialog> createState() =>
      _BatchOrganizeDialogState();
}

class _BatchOrganizeDialogState extends ConsumerState<BatchOrganizeDialog> {
  bool _running = false;
  bool _cancelled = false;
  String? _error;
  BatchProgress? _progress;
  BatchOrganizeResult? _result;
  int _totalEntries = 0;
  int _missingEntries = 0;
  int _discoveredCount = 0;

  @override
  void initState() {
    super.initState();
    ref.read(worksIndexProvider).list().then((entries) {
      if (mounted) {
        setState(() => _totalEntries = entries.length);
      }
    });
    ref.read(worksIndexProvider).listMissing().then((missing) {
      if (mounted) {
        setState(() => _missingEntries = missing.length);
      }
    });
    // 预扫描下载目录：统计未注册但可自动识别的 RJ 号作品数
    ref.read(organizeServiceProvider).discoverWorks(
      dlRoot: ref.read(downloadPathProvider),
      excludeRoot: ref.read(navidromePathProvider),
    ).then((discovered) async {
      final registered =
          (await ref.read(worksIndexProvider).list())
              .map((e) => e.sourceId)
              .toSet();
      final count = discovered
          .where((e) => !registered.contains(e.sourceId))
          .length;
      if (mounted) setState(() => _discoveredCount = count);
    });
  }

  @override
  void dispose() {
    _cancelled = true; // 对话框关闭时停止批量整理（当前作品完成后）
    super.dispose();
  }

  Future<void> _start() async {
    var targetRoot = ref.read(navidromePathProvider);
    if (targetRoot.isEmpty) {
      await ref.read(uiServiceProvider).pickNavidromePath();
      targetRoot = ref.read(navidromePathProvider);
      if (targetRoot.isEmpty) {
        setState(() => _error = '请先设置 Navidrome 整理路径');
        return;
      }
    }

    setState(() {
      _running = true;
      _cancelled = false;
      _error = null;
      _progress = null;
      _result = null;
    });

    final result = await ref.read(organizeServiceProvider).organizeAll(
      targetRoot: targetRoot,
      onlyUnorganized: ref.read(onlyOrganizeUnorganizedProvider),
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
      isCancelled: () => _cancelled,
    );

    // 整理结果变化：刷新作品库列表与 tab badge
    ref.invalidate(worksLibraryProvider);
    ref.invalidate(unorganizedCountProvider);

    if (mounted) {
      setState(() {
        _running = false;
        _result = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('批量整理'),
      content: SizedBox(width: 480, child: _buildContent(context)),
      actions: _buildActions(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_running) return _buildRunning();
    if (_result != null) return _buildDone(context);
    return _buildIdle(context);
  }

  /// 开始前的配置界面
  Widget _buildIdle(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          value: ref.watch(onlyOrganizeUnorganizedProvider),
          onChanged: (v) {
            ref.read(onlyOrganizeUnorganizedProvider.notifier).state = v ?? true;
            ref.read(configFileProvider).addOrUpdate(
                {'onlyOrganizeUnorganized': v ?? true});
          },
          title: const Text('仅整理未整理的'),
          subtitle: const Text('只处理注册表中尚未整理过的作品'),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        Text('注册表条目：$_totalEntries', style: Theme.of(context).textTheme.bodySmall),
        Text('下载目录缺失：$_missingEntries（可稍后清理）',
            style: Theme.of(context).textTheme.bodySmall),
        if (ref.read(downloadPathProvider).isNotEmpty)
          Text('自动识别未注册作品：$_discoveredCount（按 RJ 号扫描下载目录）',
              style: Theme.of(context).textTheme.bodySmall),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    );
  }

  /// 运行中的进度界面
  Widget _buildRunning() {
    final p = _progress;
    final total = p?.total ?? 0;
    final done = p?.done ?? 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (total > 0) LinearProgressIndicator(value: done / total),
        const SizedBox(height: 8),
        Text('进度：$done / $total', style: Theme.of(context).textTheme.bodySmall),
        if (p?.currentSourceId.isNotEmpty == true)
          Text('当前：${p!.currentSourceId}',
              style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        Flexible(
          child: _buildResultList(p?.results ?? const []),
        ),
      ],
    );
  }

  /// 完成后的汇总界面
  Widget _buildDone(BuildContext context) {
    final r = _result!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '完成：成功 ${r.success}，已最新 ${r.skipped}，失败 ${r.failed}，缺失 ${r.missing}${r.cancelled ? '（已取消）' : ''}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (r.missing > 0) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final cleaned = await ref.read(worksIndexProvider).cleanMissing();
              if (mounted) {
                setState(() => _missingEntries = 0);
                messenger.showSnackBar(
                    SnackBar(content: Text('已清理 $cleaned 条缺失条目')));
              }
            },
            icon: const Icon(Icons.cleaning_services, size: 16),
            label: const Text('清理缺失条目'),
          ),
        ],
        const SizedBox(height: 8),
        Flexible(child: _buildResultList(r.results)),
      ],
    );
  }

  Widget _buildResultList(List<BatchItemResult> results) {
    if (results.isEmpty) {
      return const Text('暂无结果');
    }
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: results.length,
        itemBuilder: (context, i) {
          final item = results[i];
          final icon = item.success
              ? const Icon(Icons.check_circle, size: 16, color: Colors.green)
              : const Icon(Icons.error, size: 16, color: Colors.redAccent);
          return ListTile(
            dense: true,
            leading: icon,
            title: Text(item.sourceId,
                style: Theme.of(context).textTheme.bodySmall),
            subtitle: Text(item.message,
                style: Theme.of(context).textTheme.bodySmall),
          );
        },
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    if (_running) {
      return [
        TextButton(
          onPressed: () => setState(() => _cancelled = true),
          child: const Text('取消（当前作品完成后停止）'),
        ),
      ];
    }
    if (_result != null) {
      return [
        TextButton(
          onPressed: () => showDialog(
            context: context,
            builder: (_) => const WorksIndexDialog(),
          ),
          child: const Text('管理注册表'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ];
    }
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('关闭'),
      ),
      FilledButton(
        onPressed: (_totalEntries == 0 && _discoveredCount == 0) ? null : _start,
        child: const Text('开始整理'),
      ),
    ];
  }
}
