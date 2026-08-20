import 'package:flutter/material.dart';

/// 新手引导的全屏覆盖层：半透明遮罩 + 目标区域挖洞 + 描边 + 气泡卡片。
///
/// 通过 [OnboardingController] 注入根 Navigator 的 overlay。
class OnboardingOverlay extends StatelessWidget {
  const OnboardingOverlay({
    super.key,
    required this.step,
    required this.stepCount,
    required this.title,
    required this.body,
    required this.targetRect,
    required this.onNext,
    required this.onPrev,
    required this.onSkip,
  });

  /// 当前步骤序号（0-based）
  final int step;

  /// 总步数
  final int stepCount;

  /// 气泡标题
  final String title;

  /// 气泡说明文字
  final String body;

  /// 高亮目标在屏幕上的矩形（global 坐标）
  final Rect targetRect;

  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onSkip;

  static const double _holePadding = 6;
  static const double _holeRadius = 8;
  static const double _bubbleWidth = 320;
  static const double _bubbleMaxHeight = 280;
  static const double _margin = 16;

  bool get _isLast => step == stepCount - 1;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = Offset.zero & constraints.biggest;
        return Stack(
          children: [
            // 遮罩 + 挖洞
            Positioned.fill(
              child: CustomPaint(
                painter: _HighlightPainter(
                  screen: screen,
                  hole: targetRect.inflate(_holePadding),
                  holeRadius: _holeRadius,
                ),
              ),
            ),
            // 气泡
            _buildBubble(context, screen),
          ],
        );
      },
    );
  }

  Widget _buildBubble(BuildContext context, Rect screen) {
    final scheme = Theme.of(context).colorScheme;
    final hole = targetRect.inflate(_holePadding);
    final isAbove = hole.top > screen.height / 2;

    // 气泡水平居中于目标，超出窗口时夹紧
    double bubbleLeft = hole.centerLeft.dx - _bubbleWidth / 2;
    bubbleLeft = bubbleLeft.clamp(_margin, screen.width - _bubbleWidth - _margin);

    // 垂直位置：上方优先，空间不够则下方
    double bubbleTop;
    if (isAbove) {
      bubbleTop = hole.top - _bubbleMaxHeight - _margin;
      if (bubbleTop < _margin) bubbleTop = hole.bottom + _margin;
    } else {
      bubbleTop = hole.bottom + _margin;
      if (bubbleTop + _bubbleMaxHeight > screen.height - _margin) {
        bubbleTop = hole.top - _bubbleMaxHeight - _margin;
      }
    }

    return Positioned(
      left: bubbleLeft,
      top: bubbleTop.clamp(_margin, screen.height - _margin),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: _bubbleWidth,
          maxHeight: _bubbleMaxHeight,
        ),
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 步骤序号
                Text(
                  '${step + 1} / $stepCount',
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(
                      body,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // 底部按钮
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(onPressed: onSkip, child: const Text('跳过引导')),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (step > 0)
                          TextButton(onPressed: onPrev, child: const Text('上一步')),
                        if (step > 0) const SizedBox(width: 4),
                        FilledButton(
                          onPressed: onNext,
                          child: Text(_isLast ? '开始使用' : '下一步'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 画半透明遮罩 + 在目标区域挖洞 + 圆角描边。
class _HighlightPainter extends CustomPainter {
  const _HighlightPainter({
    required this.screen,
    required this.hole,
    required this.holeRadius,
  });

  final Rect screen;
  final Rect hole;
  final double holeRadius;

  @override
  void paint(Canvas canvas, Size size) {
    // 全屏遮罩
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.7);

    // 用 Path 差集：全屏 Rect 减去 hole 区域
    final full = Path()..addRect(screen);
    final holePath = Path()
      ..addRRect(RRect.fromRectAndRadius(hole, Radius.circular(holeRadius)));
    final combined = Path.combine(PathOperation.difference, full, holePath);
    canvas.drawPath(combined, paint);

    // hole 描边
    final border = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(hole, Radius.circular(holeRadius)),
      border,
    );
  }

  @override
  bool shouldRepaint(covariant _HighlightPainter old) =>
      old.hole != hole || old.screen != screen;
}
