import 'package:asmr_downloader/pages/components/log_viewer_dialog.dart';
import 'package:flutter/material.dart';

/// 「日志」入口按钮：打开应用内实时日志查看器，
/// 无需再去应用数据目录翻日志文件。
class LogViewerButton extends StatelessWidget {
  const LogViewerButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 20.0),
      child: Tooltip(
        message: '打开应用内实时日志（无需翻日志文件）',
        child: OutlinedButton.icon(
          onPressed: () => showLogViewerDialog(context),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.white24),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            foregroundColor: Colors.white70,
          ),
          icon: const Icon(Icons.receipt_long_outlined, size: 14),
          label: const Text('日志'),
        ),
      ),
    );
  }
}
