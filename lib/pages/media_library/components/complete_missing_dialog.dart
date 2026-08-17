import 'package:asmr_downloader/services/cache/cache_complete_service.dart';
import 'package:asmr_downloader/services/cache/cache_library_providers.dart';
import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 补全媒体库中已有 workInfo 但缺少 tracks / 封面的缓存条目。
class CompleteMissingDialog extends ConsumerStatefulWidget {
  const CompleteMissingDialog({super.key});

  @override
  ConsumerState<CompleteMissingDialog> createState() =>
      _CompleteMissingDialogState();
}

class _CompleteMissingDialogState extends ConsumerState<CompleteMissingDialog> {
  bool _running = false;
  bool _cancelled = false;
  int _lastCoversFilled = 0;
  CompleteProgress? _progress;
  CompleteResult? _result;
  String? _error;

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _running = true;
      _cancelled = false;
      _lastCoversFilled = 0;
      _progress = null;
      _result = null;
      _error = null;
    });

    try {
      final result =
          await ref.read(cacheCompleteServiceProvider).completeMissing(
                onProgress: (progress) {
                  if (!mounted) return;
                  if (progress.coversFilled > _lastCoversFilled &&
                      progress.currentSourceId.isNotEmpty) {
                    ref.invalidate(
                      cachedCoverProvider(progress.currentSourceId),
                    );
                  }
                  _lastCoversFilled = progress.coversFilled;
                  setState(() => _progress = progress);
                },
                isCancelled: () => _cancelled,
              );
      if (!mounted) return;
      setState(() {
        _running = false;
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = '补全失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('补全缺失'),
      content: SizedBox(width: 480, child: _buildContent(context)),
      actions: _buildActions(),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_running) return _buildRunning();
    if (_result != null) return _buildDone();
    return _buildIdle(context);
  }

  Widget _buildIdle(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('将扫描已缓存的 workInfo，只请求缺少的 tracks 和封面。'),
        const SizedBox(height: 8),
        Text(
          '每个作品按全局限速逐条处理，可随时取消；已有缓存不会重复请求。',
          style: theme.textTheme.bodySmall,
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }

  Widget _buildRunning() {
    final progress = _progress;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LinearProgressIndicator(),
        const SizedBox(height: 10),
        Text(
          'tracks：${progress?.tracksFilled ?? 0} / ${progress?.totalTracksMissing ?? '…'}，'
          '封面：${progress?.coversFilled ?? 0} / ${progress?.totalCoversMissing ?? '…'}，'
          '失败：${progress?.failed ?? 0}',
          style: theme.textTheme.bodyMedium,
        ),
        if (progress?.currentSourceId.isNotEmpty == true) ...[
          const SizedBox(height: 4),
          Text(
            '当前：${progress!.currentSourceId}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _buildDone() {
    final result = _result!;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '已补全 tracks ${result.tracksFilled} 个、封面 ${result.coversFilled} 个，'
          '失败 ${result.failed} 个${result.cancelled ? '（已取消）' : ''}。',
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }

  List<Widget> _buildActions() {
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
      FilledButton(
        onPressed: _start,
        child: const Text('开始补全'),
      ),
    ];
  }
}
