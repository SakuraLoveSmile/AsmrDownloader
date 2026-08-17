import 'package:asmr_downloader/services/transcribe/chicken_rice_service.dart';
import 'package:asmr_downloader/services/transcribe/transcribe_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 全局 AI 字幕运行状态指示器（工具栏用）：
/// 空闲时显示「字幕」入口（点击对作品库当前选中/全部缺字幕作品生成）；
/// 运行中显示进度（启动中…/百分比/当前文件）+ 实时日志入口 + 取消按钮。
///
/// 直调 infer.exe 后不再有 bat 控制台窗口，ChickenRice 的输出
/// （stdout/stderr 逐行）改由本指示器的日志弹窗实时展示。
class TranscribeStatusIndicator extends ConsumerWidget {
  const TranscribeStatusIndicator({super.key, this.onStart});

  /// 空闲时点击「字幕」的回调（由宿主页面决定对哪些作品生成）。
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(transcribeStatusProvider);
    final progress = ref.watch(transcribeProgressProvider);
    final hasLog = ref.watch(transcribeLogLinesProvider).isNotEmpty;
    final running = status == TranscribeStatus.running;
    final ui = ref.read(uiServiceProvider);
    final scheme = Theme.of(context).colorScheme;

    return running
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _runningLabel(progress),
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
              ),
              IconButton(
                onPressed: () => _showLogDialog(context),
                icon: const Icon(Icons.receipt_long_outlined, size: 16),
                tooltip: '查看实时日志',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: ui.cancelTranscribe,
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                tooltip: '取消字幕翻译',
                visualDensity: VisualDensity.compact,
              ),
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton(
                onPressed: onStart,
                child: const Text('字幕'),
              ),
              // 上次运行的日志仍可查看（便于失败后排查）
              if (hasLog)
                IconButton(
                  onPressed: () => _showLogDialog(context),
                  icon: const Icon(Icons.receipt_long_outlined, size: 16),
                  tooltip: '查看上次字幕运行日志',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          );
  }

  /// 运行中的状态文案：尚无进度行时显示「启动中…」
  /// （PyInstaller 解包 + 模型加载阶段无任何 n/total 输出）。
  static String _runningLabel(TranscribeProgress? p) {
    if (p == null) return '字幕 启动中…';
    final pct = (p.percentage * 100).toStringAsFixed(0);
    final file = p.currentFile.isEmpty ? '' : ' · ${p.currentFile}';
    final vad = p.subPercentage == null
        ? ''
        : '（VAD ${(p.subPercentage! * 100).toStringAsFixed(0)}%）';
    return '字幕 $pct%（${p.done}/${p.total}）$file$vad';
  }

  void _showLogDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const _TranscribeLogDialog(),
    );
  }
}

/// 实时日志弹窗：订阅 [transcribeLogLinesProvider] 逐行展示
/// ChickenRice 输出；默认跟随尾部滚动，用户上滑查看历史时暂停跟随。
class _TranscribeLogDialog extends ConsumerStatefulWidget {
  const _TranscribeLogDialog();

  @override
  ConsumerState<_TranscribeLogDialog> createState() =>
      _TranscribeLogDialogState();
}

class _TranscribeLogDialogState extends ConsumerState<_TranscribeLogDialog> {
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
      if (!_controller.hasClients) return;
      _controller.jumpTo(_controller.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(transcribeLogLinesProvider);
    final scheme = Theme.of(context).colorScheme;
    _scheduleScrollToEnd();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '字幕运行日志（ChickenRice 实时输出）',
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 13),
                    ),
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
                  child: lines.isEmpty
                      ? Center(
                          child: Text('暂无日志',
                              style: TextStyle(color: scheme.onSurfaceVariant)),
                        )
                      : NotificationListener<ScrollUpdateNotification>(
                          // 用户手动上滑 → 暂停跟随；滚回底部 → 恢复跟随
                          onNotification: (n) {
                            if (n.dragDetails == null ||
                                !_controller.hasClients) {
                              return false;
                            }
                            final pos = _controller.position;
                            _follow = pos.pixels >= pos.maxScrollExtent - 24;
                            return false;
                          },
                          child: ListView.builder(
                            controller: _controller,
                            itemCount: lines.length,
                            itemBuilder: (_, i) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1),
                              child: Text(
                                lines[i],
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
