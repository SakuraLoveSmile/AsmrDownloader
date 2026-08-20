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
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant, width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 步骤胶囊徽标
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '${step + 1} / $stepCount 步骤',
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(
                      body,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // 底部胶囊按钮
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: onSkip,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: scheme.onSurfaceVariant,
                      ),
                      child: const Text('跳过引导', style: TextStyle(fontSize: 12)),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (step > 0)
                          TextButton(
                            onPressed: onPrev,
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            child: const Text('上一步', style: TextStyle(fontSize: 12)),
                          ),
                        if (step > 0) const SizedBox(width: 4),
                        FilledButton(
                          onPressed: onNext,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(
                            _isLast ? '开始使用' : '下一步',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
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

/// 画半透明遮罩 + 在目标区域挖洞 + 圆角发光描边。
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
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.65);

    // 用 Path 差集：全屏 Rect 减去 hole 区域
    final full = Path()..addRect(screen);
    final holePath = Path()
      ..addRRect(RRect.fromRectAndRadius(hole, Radius.circular(holeRadius)));
    final combined = Path.combine(PathOperation.difference, full, holePath);
    canvas.drawPath(combined, paint);

    // hole 发光外圈与亮色细描边
    final border = Paint()
      ..color = const Color(0xFF0A84FF).withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(hole, Radius.circular(holeRadius)),
      border,
    );
  }

  @override
  bool shouldRepaint(covariant _HighlightPainter old) =>
      old.hole != hole || old.screen != screen;
}
