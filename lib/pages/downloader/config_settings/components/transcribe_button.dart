import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/transcribe/chicken_rice_service.dart';
import 'package:asmr_downloader/services/transcribe/transcribe_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 手动触发 ChickenRice 为当前作品生成 AI 字幕，并展示进度/取消。
class TranscribeButton extends ConsumerWidget {
  const TranscribeButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloading =
        ref.watch(dlStatusProvider) == DownloadStatus.downloading;
    final status = ref.watch(transcribeStatusProvider);
    final progress = ref.watch(transcribeProgressProvider);
    final running = status == TranscribeStatus.running;
    final ui = ref.read(uiServiceProvider);

    return SizedBox(
      child: Padding(
        padding: const EdgeInsets.only(left: 20.0),
        child: running
            ? Row(
                children: [
                  _ProgressLabel(progress: progress),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: ui.cancelTranscribe,
                    icon: const Icon(Icons.stop_circle_outlined),
                    tooltip: '取消字幕翻译',
                  ),
                ],
              )
            : OutlinedButton(
                onPressed: (downloading || running)
                    ? null
                    : () => ui.transcribeCurrentWork(
                        pickExeIfEmpty: true),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white24),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  foregroundColor: Colors.white70,
                  disabledForegroundColor: Colors.white24,
                ),
                child: const Text('字幕'),
              ),
      ),
    );
  }
}

class _ProgressLabel extends StatelessWidget {
  final TranscribeProgress? progress;
  const _ProgressLabel({required this.progress});

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final pct = p == null
        ? '..'
        : '${(p.percentage * 100).toStringAsFixed(0)}%';
    return Text('字幕 $pct',
        style: const TextStyle(color: Colors.white70, fontSize: 12));
  }
}
