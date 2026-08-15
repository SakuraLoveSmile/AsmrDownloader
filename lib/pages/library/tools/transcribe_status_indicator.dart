import 'package:asmr_downloader/services/transcribe/transcribe_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 全局 AI 字幕运行状态指示器（工具栏用）：
/// 空闲时显示「字幕」入口（点击对作品库当前选中/全部缺字幕作品生成）；
/// 运行中显示进度百分比 + 取消按钮。
class TranscribeStatusIndicator extends ConsumerWidget {
  const TranscribeStatusIndicator({super.key, this.onStart});

  /// 空闲时点击「字幕」的回调（由宿主页面决定对哪些作品生成）。
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(transcribeStatusProvider);
    final progress = ref.watch(transcribeProgressProvider);
    final running = status == TranscribeStatus.running;
    final ui = ref.read(uiServiceProvider);

    return Padding(
      padding: const EdgeInsets.only(left: 20.0),
      child: running
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '字幕 ${progress == null ? '..' : '${(progress.percentage * 100).toStringAsFixed(0)}%'}',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12),
                ),
                const SizedBox(width: 6),
                IconButton(
                  onPressed: ui.cancelTranscribe,
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  tooltip: '取消字幕翻译',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            )
          : OutlinedButton(
              onPressed: onStart,
              child: const Text('字幕'),
            ),
    );
  }
}
