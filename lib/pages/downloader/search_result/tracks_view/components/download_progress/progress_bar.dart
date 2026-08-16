import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/pages/components/middle_ellipsis_text.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 分段下载进度条：每个文件占一段（段宽按字节占比），段内独立填充，
/// 并行下载时可直观看到每个文件各自的进度。
/// 无分段数据（未开始/字节信息缺失）时回退为普通整体进度条。
class ProgressBar extends ConsumerWidget {
  const ProgressBar({super.key});

  static const double _barHeight = 26;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segments = ref.watch(downloadSegmentsProvider);
    final process = ref.watch(processProvider);
    final status = ref.watch(dlStatusProvider);
    final activeFileNames = ref.watch(activeFileNamesProvider);

    final scheme = Theme.of(context).colorScheme;
    final bar = segments.isEmpty
        ? LinearProgressIndicator(
            minHeight: _barHeight,
            borderRadius: BorderRadius.circular(8),
            value: process,
          )
        : SizedBox(
            height: _barHeight,
            width: double.infinity,
            child: CustomPaint(
              painter: _SegmentedBarPainter(
                segments: segments,
                trackColor: scheme.surfaceContainerHighest,
                fillColor: scheme.primary,
                failedColor: scheme.error,
              ),
            ),
          );

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          bar,
          const SizedBox(height: 4),
          _ProgressCaption(status: status, activeFileNames: activeFileNames),
        ],
      ),
    );
  }
}

/// 进度条下方的说明文案：下载中显示活动文件名，其余状态显示结果提示。
class _ProgressCaption extends StatelessWidget {
  const _ProgressCaption({required this.status, required this.activeFileNames});

  final DownloadStatus status;
  final List<String> activeFileNames;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    const textStyleBase = TextStyle(height: 1.0, fontSize: 12);

    if (activeFileNames.isNotEmpty) {
      final displayText = switch (activeFileNames.length) {
        1 => activeFileNames.first,
        2 => activeFileNames.join('、'),
        _ =>
          '${activeFileNames.take(2).join('、')} 等 ${activeFileNames.length} 个文件',
      };
      return Row(
        children: ellipsisInMiddle(
          displayText,
          textStyle: textStyleBase.copyWith(color: color),
        ),
      );
    }

    final caption = switch (status) {
      DownloadStatus.completed => '下载完成',
      DownloadStatus.canceled => '下载已取消',
      DownloadStatus.failed => '部分文件下载失败',
      _ => '',
    };
    if (caption.isEmpty) return const SizedBox.shrink();
    return Text(caption, style: textStyleBase.copyWith(color: color));
  }
}

/// 按文件分段绘制的进度条：段宽与文件字节占比成正比（大小未知时等宽），
/// 段内按该文件自身进度填充，失败文件已下载部分以错误色标出。
class _SegmentedBarPainter extends CustomPainter {
  _SegmentedBarPainter({
    required this.segments,
    required this.trackColor,
    required this.fillColor,
    required this.failedColor,
  });

  static const double _gap = 2;
  static final BorderRadius _borderRadius = BorderRadius.circular(8);

  final List<DownloadSegment> segments;
  final Color trackColor;
  final Color fillColor;
  final Color failedColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty || size.width <= 0 || size.height <= 0) return;

    canvas.save();
    canvas.clipRRect(
        _borderRadius.resolve(TextDirection.ltr).toRRect(Offset.zero & size));

    final totalSize = segments.fold<int>(0, (sum, s) => sum + s.size);
    final availableWidth =
        size.width - _gap * (segments.length - 1).clamp(0, segments.length);
    final trackPaint = Paint()..color = trackColor;

    var x = 0.0;
    for (final segment in segments) {
      final width = totalSize > 0
          ? availableWidth * segment.size / totalSize
          : availableWidth / segments.length;
      final rect = Rect.fromLTWH(x, 0, width, size.height);
      canvas.drawRect(rect, trackPaint);

      if (segment.fraction > 0) {
        final fillPaint = Paint()
          ..color =
              segment.status == DownloadStatus.failed ? failedColor : fillColor;
        canvas.drawRect(
          Rect.fromLTWH(x, 0, width * segment.fraction, size.height),
          fillPaint,
        );
      }
      x += width + _gap;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SegmentedBarPainter oldDelegate) {
    return !identical(oldDelegate.segments, segments) ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.failedColor != failedColor;
  }
}
