import 'package:asmr_downloader/utils/log.dart';
import 'package:asmr_downloader/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 弹出应用内实时日志查看器。
Future<void> showLogViewerDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const LogViewerDialog(),
  );
}

/// 应用内「在线日志」查看器：订阅 [Log.buffer] 实时展示本次启动以来的
/// 全部应用日志（无需再去应用数据目录翻日志文件）。
///
/// 默认跟随尾部滚动，用户上滑查看历史时暂停跟随；支持一键复制与清空。
class LogViewerDialog extends StatefulWidget {
  const LogViewerDialog({super.key});

  @override
  State<LogViewerDialog> createState() => _LogViewerDialogState();
}

class _LogViewerDialogState extends State<LogViewerDialog> {
  final ScrollController _controller = ScrollController();

  /// 是否自动跟随尾部（用户上滑时置 false，回到底部恢复）
  bool _follow = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scheduleScrollToEnd() {
    if (!_follow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.jumpTo(_controller.position.maxScrollExtent);
    });
  }

  Future<void> _copyAll(List<LogEntry> entries) async {
    await Clipboard.setData(
      ClipboardData(text: entries.map((e) => e.format()).join('\n')),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制 ${entries.length} 条日志到剪贴板')),
    );
  }

  void _clearLogs() {
    Log.buffer.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清空日志')),
    );
  }

  Color _levelColor(String level) {
    switch (level) {
      case 'ERROR':
      case 'FATAL':
        return AppColors.danger;
      case 'WARN':
        return AppColors.warning;
      case 'INFO':
        return Theme.of(context).colorScheme.onSurfaceVariant;
      default: // TRACE / DEBUG
        return Theme.of(context)
            .colorScheme
            .onSurfaceVariant
            .withValues(alpha: 0.6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: Log.buffer,
      builder: (context, _) {
        final entries = Log.buffer.entries;
        _scheduleScrollToEnd();
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860, maxHeight: 600),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '应用日志（实时）· ${entries.length} 条',
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 13),
                        ),
                      ),
                      IconButton(
                        onPressed:
                            entries.isEmpty ? null : () => _copyAll(entries),
                        icon: const Icon(Icons.copy_all_outlined, size: 16),
                        tooltip: '复制全部日志',
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        onPressed: entries.isEmpty ? null : _clearLogs,
                        icon: const Icon(Icons.delete_outline, size: 17),
                        tooltip: '清空日志',
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: '关闭',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.only(right: 8),
                      child: entries.isEmpty
                          ? Center(
                              child: Text('暂无日志',
                                  style: TextStyle(
                                      color: scheme.onSurfaceVariant)),
                            )
                          : NotificationListener<ScrollUpdateNotification>(
                              // 用户手动上滑 → 暂停跟随；滚回底部 → 恢复跟随
                              onNotification: (n) {
                                if (n.dragDetails == null ||
                                    !_controller.hasClients) {
                                  return false;
                                }
                                final pos = _controller.position;
                                _follow =
                                    pos.pixels >= pos.maxScrollExtent - 24;
                                return false;
                              },
                              child: ListView.builder(
                                controller: _controller,
                                itemCount: entries.length,
                                itemBuilder: (_, i) {
                                  final e = entries[i];
                                  return Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 1),
                                    child: SelectableText(
                                      e.format(),
                                      style: TextStyle(
                                        color: _levelColor(e.level),
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                        height: 1.3,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
