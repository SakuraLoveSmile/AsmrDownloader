import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/transcribe/transcribe_providers.dart';
import 'package:asmr_downloader/services/update/update_providers.dart';
import 'package:asmr_downloader/services/update/update_service.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 弹出「发现新版本」更新对话框。
Future<void> showUpdateDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const UpdateDialog(),
  );
}

/// 版本更新对话框：展示新版本与更新日志，确认后自动下载安装包；
/// 安装前二次确认（会退出应用），由更新脚本完成文件替换与重启。
class UpdateDialog extends ConsumerStatefulWidget {
  const UpdateDialog({super.key});

  @override
  ConsumerState<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<UpdateDialog> {
  bool _downloading = false;

  /// 下载完成、等待用户二次确认安装
  bool _readyToInstall = false;
  bool _installing = false;
  String? _error;

  /// 第一步：确认更新 → 下载安装包（debug 构建降级打开 Release 页面）
  Future<void> _startDownload(UpdateInfo info) async {
    if (!kReleaseMode) {
      // debug 构建的可执行文件是 Flutter 工具链产物，不能替换；降级打开网页
      await ref.read(updateServiceProvider).openReleasePage(info);
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() {
      _downloading = true;
      _error = null;
    });
    final result = await ref
        .read(latestUpdateProvider.notifier)
        .downloadUpdatePackage(info);
    if (!mounted) return;
    if (result == null) {
      // 下载完成：进入安装前二次确认
      setState(() {
        _downloading = false;
        _readyToInstall = true;
      });
      return;
    }
    if (result.isEmpty) {
      // 用户取消下载
      setState(() => _downloading = false);
      return;
    }
    setState(() {
      _downloading = false;
      _error = result;
    });
  }

  /// 第二步：二次确认安装 → 退出应用，脚本接管替换与重启
  Future<void> _confirmInstall() async {
    setState(() {
      _installing = true;
      _error = null;
    });
    final result =
        await ref.read(latestUpdateProvider.notifier).installUpdate();
    if (!mounted) return;
    if (result == null) return; // 应用即将退出
    setState(() {
      _installing = false;
      _readyToInstall = false;
      _error = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = ref.watch(latestUpdateProvider).valueOrNull;
    if (info == null) {
      return AlertDialog(
        title: const Text('检查更新'),
        content: const Text('当前已是最新版本。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      );
    }

    final currentVersion = ref.watch(appVersionProvider).valueOrNull ?? '';
    final progress = ref.watch(updateDownloadProgressProvider);
    // 有下载/转录任务运行时禁止安装：安装会直接退出应用，打断任务
    final taskRunning =
        ref.watch(dlStatusProvider) == DownloadStatus.downloading ||
            ref.watch(transcribeStatusProvider) == TranscribeStatus.running;

    return AlertDialog(
      title: Text('发现新版本 ${info.tagName}'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '当前版本：${currentVersion.isEmpty ? '未知' : 'v$currentVersion'}',
              style: theme.textTheme.bodySmall!.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            if (info.releaseNotes.trim().isNotEmpty) ...[
              Text('更新内容：', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: SingleChildScrollView(
                  child: SelectableText(
                    info.releaseNotes,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            ],
            if (_downloading) ...[
              const SizedBox(height: 12),
              _progressView(theme, progress),
            ],
            if (_installing) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text('正在安装，应用即将退出…', style: theme.textTheme.bodySmall),
                ],
              ),
            ],
            if (_readyToInstall && !_installing) ...[
              const SizedBox(height: 12),
              Text(
                '更新包已下载完成。继续安装将退出当前应用，'
                '替换文件后自动重启。',
                style: theme.textTheme.bodySmall!.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: theme.textTheme.bodySmall!
                    .copyWith(color: theme.colorScheme.error),
              ),
            ],
            if (taskRunning && !_downloading && !_installing) ...[
              const SizedBox(height: 12),
              Text(
                '有下载或 AI 字幕任务正在运行，请等待完成后再更新'
                '（更新会退出并重启应用）。',
                style: theme.textTheme.bodySmall!.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: _buildActions(info, taskRunning),
    );
  }

  Widget _progressView(ThemeData theme, UpdateDownloadProgress? progress) {
    final total = progress?.total ?? 0;
    final received = progress?.received ?? 0;
    final value = total > 0 ? received / total : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: value),
        const SizedBox(height: 6),
        Text(
          value == null
              ? '正在下载更新包…'
              : '正在下载更新包 ${getSizeString(received)} / '
                  '${getSizeString(total)}',
          style: theme.textTheme.bodySmall!.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildActions(UpdateInfo info, bool taskRunning) {
    if (_downloading) {
      return [
        TextButton(
          onPressed: () =>
              ref.read(latestUpdateProvider.notifier).cancelDownload(),
          child: const Text('取消下载'),
        ),
      ];
    }
    if (_installing) return const [];
    if (_readyToInstall) {
      return [
        TextButton(
          onPressed: () => setState(() => _readyToInstall = false),
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: taskRunning ? null : _confirmInstall,
          child: const Text('确认安装并重启'),
        ),
      ];
    }
    return [
      if (_error != null)
        TextButton(
          onPressed: () =>
              ref.read(updateServiceProvider).openReleasePage(info),
          child: const Text('打开下载页面'),
        ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('稍后'),
      ),
      FilledButton(
        onPressed: taskRunning ? null : () => _startDownload(info),
        child: const Text('立即更新'),
      ),
    ];
  }
}
