import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NavidromePathPicker extends ConsumerWidget {
  const NavidromePathPicker({super.key});

  final Color _color = Colors.white70;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navidromePath = ref.watch(navidromePathProvider);
    return SizedBox(
      height: 50.0,
      child: Padding(
        padding: const EdgeInsets.only(left: 20.0),
        child: Row(
          children: [
            SizedBox(
              width: 180,
              child: TextField(
                enabled: false,
                cursorColor: _color,
                decoration: InputDecoration(
                  hintText: navidromePath.isEmpty ? '选择整理路径' : navidromePath,
                  border: OutlineInputBorder(),
                  focusedBorder:
                      OutlineInputBorder(borderSide: BorderSide(color: _color)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 5.0),
              child: IconButton(
                onPressed: ref.read(uiServiceProvider).pickNavidromePath,
                icon: const Icon(Icons.folder),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
