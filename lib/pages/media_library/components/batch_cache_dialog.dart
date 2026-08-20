import 'package:asmr_downloader/services/cache/batch_cache_service.dart';
import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 主动缓存对话框：
/// - 空闲态：选择维度（标签/社团/CV）、输入名称、说明限速行为
/// - 运行态：不确定进度条 + 计数 + 当前作品 + 取消（当前作品完成后停止）
/// - 完成态：汇总（含取消标记）+ 关闭
class BatchCacheDialog extends ConsumerStatefulWidget {
  const BatchCacheDialog({super.key});

  @override
  ConsumerState<BatchCacheDialog> createState() => _BatchCacheDialogState();
}

class _BatchCacheDialogState extends ConsumerState<BatchCacheDialog> {
  BatchCacheDimension _dimension = BatchCacheDimension.tag;
  final _nameController = TextEditingController();

  /// 可选申请间隔（秒）。null 表示使用默认 2 秒
  Duration? _interval;

  bool _running = false;
  bool _cancelled = false;
  BatchCacheProgress? _progress;
  BatchCacheResult? _result;
  String? _error;

  @override
  void dispose() {
    _cancelled = true; // 对话框关闭时停止批量缓存（当前作品完成后）
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _running = true;
      _cancelled = false;
      _progress = null;
      _result = null;
      _error = null;
    });

    try {
      final result = await ref.read(batchCacheServiceProvider).batchCache(
            _dimension,
            name,
            runInterval: _interval,
            onProgress: (p) {
              if (mounted) setState(() => _progress = p);
            },
            isCancelled: () => _cancelled,
          );
      if (mounted) {
        setState(() {
          _running = false;
          _result = result;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _running = false;
          _error = '缓存失败: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('主动缓存'),
      content: SizedBox(width: 480, child: _buildContent(context)),
      actions: _buildActions(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_running) return _buildRunning();
    if (_result != null) return _buildDone();
    return _buildIdle(context);
  }

  /// 开始前的配置界面
  Widget _buildIdle(BuildContext context) {
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
          onChanged: (v) {
            if (v != null) setState(() => _dimension = v);
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
        DropdownButtonFormField<Duration?>(
          initialValue: _interval,
          decoration: const InputDecoration(labelText: '请求间隔（限速）'),
          items: [
            const DropdownMenuItem(
              value: null,
              child: Text('默认（每个作品约 2 秒）'),
            ),
            for (final ms in const [500, 1000, 2000, 3000, 5000])
              DropdownMenuItem(
                value: Duration(milliseconds: ms),
                child: Text(
                    ms < 1000 ? '${ms / 1000} 秒 / 个' : '${ms ~/ 1000} 秒 / 个'),
              ),
          ],
          onChanged: (v) => setState(() => _interval = v),
        ),
        const SizedBox(height: 12),
        Text(
          '将逐个获取 workInfo 写入本地缓存（已缓存自动跳过）。'
          '间隔越小耗时越短但对网站越激进，请根据网络与合作方节奏选择。'
          '（如按默认 2 秒，100 个作品约需 3 分钟。）可随时取消。',
          style: theme.textTheme.bodySmall,
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }

  /// 运行中的进度界面
  Widget _buildRunning() {
    final p = _progress;
    final theme = Theme.of(context);
    final total = p?.total;
    // 已知总数时用确定进度；未知（如还没有首个搜索页）用不确定进度
    final hasTotal = total != null && total > 0;
    final value = hasTotal ? (p!.cached / total).clamp(0.0, 1.0) : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: value),
        const SizedBox(height: 8),
        Text(
          hasTotal
              ? '已缓存 ${p!.cached} / $total'
                  '${p.totalApprox ? '（约）' : ''}'
                  '，跳过 ${p.skipped}，失败 ${p.failed}'
              : '已缓存 ${p?.cached ?? 0}，跳过 ${p?.skipped ?? 0}，失败 ${p?.failed ?? 0}',
          style: theme.textTheme.bodyMedium,
        ),
        if (p?.currentSourceId.isNotEmpty == true) ...[
          const SizedBox(height: 4),
          Text('当前：${p!.currentSourceId}', style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }

  /// 完成后的汇总界面
  Widget _buildDone() {
    final r = _result!;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          r.total != null
              ? '本次预计 ${r.total} 项：缓存 ${r.cached} 个，'
                  '跳过 ${r.skipped} 个，失败 ${r.failed} 个'
                  '${r.cancelled ? '（已取消）' : ''}'
              : '缓存 ${r.cached} 个，跳过 ${r.skipped} 个，失败 ${r.failed} 个'
                  '${r.cancelled ? '（已取消）' : ''}',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Text(
          '仅缓存 workInfo 元数据，后续搜索时 tracks / 封面仍按需获取。',
          style: theme.textTheme.bodySmall,
        ),
        if (r.failedSourceIds.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '失败作品：${r.failedSourceIds.take(10).join('、')}'
            '${r.failedSourceIds.length > 10 ? ' 等 ${r.failedSourceIds.length} 个' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
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
      // 名称为空时禁用开始按钮（随输入实时更新）
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: _nameController,
        builder: (context, value, _) => FilledButton(
          onPressed: value.text.trim().isEmpty ? null : _start,
          child: const Text('开始缓存'),
        ),
      ),
    ];
  }
}

/// 主动缓存按钮：打开主动缓存对话框。
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
