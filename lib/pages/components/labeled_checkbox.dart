import 'package:flutter/material.dart';

/// 带文字标签的紧凑复选框：点击文字或复选框均可切换。
///
/// 替代「Text + 裸 Checkbox」的散落写法，统一工具栏开关样式。
class LabeledCheckbox extends StatelessWidget {
  const LabeledCheckbox({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final textColor = enabled
        ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8)
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35);
    return InkWell(
      onTap: enabled ? () => onChanged!(!value) : null,
      borderRadius: BorderRadius.circular(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: textColor)),
          const SizedBox(width: 2),
          Checkbox(
            value: value,
            onChanged: onChanged,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
