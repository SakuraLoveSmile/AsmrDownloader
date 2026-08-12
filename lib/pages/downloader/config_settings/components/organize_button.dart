import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 整理当前作品到 Navidrome 媒体库。
/// 整理路径未设置时点击会自动弹出目录选择器。
class OrganizeButton extends ConsumerWidget {
  const OrganizeButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloading =
        ref.watch(dlStatusProvider) == DownloadStatus.downloading;

    return SizedBox(
      child: Padding(
        padding: const EdgeInsets.only(left: 20.0),
        child: OutlinedButton(
          onPressed: downloading
              ? null
              : () => ref.read(uiServiceProvider).organizeToNavidrome(context),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.white24),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            foregroundColor: Colors.white70,
            disabledForegroundColor: Colors.white24,
          ),
          child: const Text('整理'),
        ),
      ),
    );
  }
}
