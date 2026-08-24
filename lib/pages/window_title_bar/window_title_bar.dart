import 'package:asmr_downloader/common/const.dart';
import 'package:asmr_downloader/pages/update/update_entry.dart';
import 'package:asmr_downloader/pages/window_title_bar/caption_buttons/window_caption_buttons.dart';
// ignore: unused_import
import 'package:asmr_downloader/pages/window_title_bar/move_window.dart';
import 'package:flutter/material.dart';

class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({
    super.key,
    this.title,
  });

  final Text? title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 0.8),
        ),
      ),
      child: MoveWindow(
        child: SizedBox(
          width: double.infinity,
          height: TITLEBAR_HEIGHT,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: title!,
                ),
              const Spacer(),
              // 版本号 + 检查更新入口
              const UpdateEntry(),
              const SizedBox(width: 4),
              CaptionButtons(),
            ],
          ),
        ),
      ),
    );
  }
}
