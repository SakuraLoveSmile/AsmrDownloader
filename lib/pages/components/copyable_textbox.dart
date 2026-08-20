import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CopyableTextBox extends StatelessWidget {
  final String text;
  final TextStyle? textStyle;
  final Color backgroundColor;
  final BoxBorder? border;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const CopyableTextBox({
    super.key,
    required this.text,
    this.textStyle,
    this.backgroundColor = Colors.transparent,
    this.border,
    this.borderRadius = 8.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '点击复制: $text',
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: text));
          },
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              border: border,
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            child: Text(text, style: textStyle),
          ),
        ),
      ),
    );
  }
}
