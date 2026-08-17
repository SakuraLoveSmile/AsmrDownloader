import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Navidrome 整理目标路径选择器
class NavidromePathPicker extends ConsumerWidget {
  const NavidromePathPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navidromePath = ref.watch(navidromePathProvider);
    return Row(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 160, maxWidth: 220),
          child: TextField(
            enabled: false,
            decoration: InputDecoration(
              hintText: navidromePath.isEmpty ? '选择整理路径' : navidromePath,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 5.0),
          child: IconButton(
            onPressed: ref.read(uiServiceProvider).pickNavidromePath,
            icon: const Icon(Icons.folder),
            tooltip: '选择整理路径',
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}
