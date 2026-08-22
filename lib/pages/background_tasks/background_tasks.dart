import 'package:asmr_downloader/services/tasks/background_task_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 应用内长耗时操作的统一任务中心。
///
/// 任务在应用进程内继续执行，切换到其他页面不会中断；
/// 当前支持媒体库的「主动缓存」和「一键补全」。
class BackgroundTasksPage extends ConsumerWidget {
  const BackgroundTasksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(backgroundTaskProvider);
    final activeCount = tasks.where((task) => task.isActive).length;
    final finishedCount = tasks.where((task) => task.isFinished).length;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbar(
          context,
          ref,
          activeCount: activeCount,
          finishedCount: finishedCount,
        ),
        const Divider(height: 1),
        Expanded(
          child: tasks.isEmpty
              ? _EmptyTasks(color: scheme.onSurfaceVariant)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                  itemCount: tasks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final task = tasks[tasks.length - index - 1];
                    return _BackgroundTaskCard(
                      task: task,
                      onCancel: () => ref
                          .read(backgroundTaskProvider.notifier)
                          .cancelTask(task.id),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildToolbar(
    BuildContext context,
    WidgetRef ref, {
    required int activeCount,
    required int finishedCount,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      child: Container(
        key: const ValueKey('background-tasks-toolbar'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant, width: 0.8),
        ),
        child: Row(
          children: [
            Icon(Icons.task_alt_rounded, size: 20, color: scheme.primary),
            const SizedBox(width: 10),
            const Text(
              '后台任务',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 10),
            _CountPill(
              label: activeCount > 0 ? '进行中 $activeCount' : '暂无进行中任务',
              color: activeCount > 0 ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const Spacer(),
            if (finishedCount > 0)
              TextButton.icon(
                onPressed: () =>
                    ref.read(backgroundTaskProvider.notifier).clearFinished(),
                icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                label: const Text('清除历史'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color == scheme.onSurfaceVariant
              ? scheme.onSurfaceVariant
              : color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _BackgroundTaskCard extends StatelessWidget {
  const _BackgroundTaskCard({required this.task, required this.onCancel});

  final BackgroundTask task;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, statusLabel) = _statusVisual(scheme);
    final progress = task.progress;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 10, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: task.status == BackgroundTaskStatus.running
              ? scheme.primary.withValues(alpha: 0.45)
              : scheme.outlineVariant,
          width: task.status == BackgroundTaskStatus.running ? 1.0 : 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 19, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      task.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _StatusPill(label: statusLabel, color: color),
              if (task.isActive)
                IconButton(
                  onPressed: onCancel,
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  tooltip: task.status == BackgroundTaskStatus.queued
                      ? '取消排队任务'
                      : '取消任务',
                  visualDensity: VisualDensity.compact,
                  color: scheme.error,
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (task.status == BackgroundTaskStatus.queued)
            Text(
              '等待前序任务完成后开始',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            )
          else ...[
            LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: scheme.surfaceContainerHighest,
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _counterText(),
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11.5,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    task.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: task.status == BackgroundTaskStatus.failed
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (task.currentSourceId.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              '当前：${task.currentSourceId}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
            ),
          ],
          if (task.error != null) ...[
            const SizedBox(height: 5),
            Text(
              task.error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.error, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  String _counterText() {
    final total = task.total == null ? '' : ' / ${task.total}';
    return '处理 ${task.processed}$total · 成功 ${task.success} · 跳过 ${task.skipped} · 失败 ${task.failed}';
  }

  (IconData, Color, String) _statusVisual(ColorScheme scheme) {
    switch (task.status) {
      case BackgroundTaskStatus.queued:
        return (Icons.schedule_rounded, scheme.onSurfaceVariant, '排队中');
      case BackgroundTaskStatus.running:
        return (
          Icons.downloading_rounded,
          scheme.primary,
          task.cancelRequested ? '取消中' : '运行中',
        );
      case BackgroundTaskStatus.completed:
        return (Icons.check_circle_rounded, Colors.green, '已完成');
      case BackgroundTaskStatus.failed:
        return (Icons.error_rounded, scheme.error, '失败');
      case BackgroundTaskStatus.canceled:
        return (Icons.stop_circle_rounded, scheme.onSurfaceVariant, '已取消');
    }
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyTasks extends StatelessWidget {
  const _EmptyTasks({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.task_alt_rounded, size: 48, color: color),
          const SizedBox(height: 12),
          Text(
            '暂无后台任务',
            style: TextStyle(color: color, fontSize: 14),
          ),
          const SizedBox(height: 5),
          Text(
            '媒体库的批量缓存和一键补全操作会显示在这里。',
            style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 12),
          ),
        ],
      ),
    );
  }
}
