import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 主题模式选择器：深色 / 浅色 / 跟随系统。
class ThemeModeSelector extends ConsumerWidget {
  const ThemeModeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '主题外观',
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'dark',
              icon: Icon(Icons.dark_mode_rounded, size: 14),
              label: Text('深色', style: TextStyle(fontSize: 11.5)),
            ),
            ButtonSegment(
              value: 'light',
              icon: Icon(Icons.light_mode_rounded, size: 14),
              label: Text('浅色', style: TextStyle(fontSize: 11.5)),
            ),
            ButtonSegment(
              value: 'system',
              icon: Icon(Icons.brightness_auto_rounded, size: 14),
              label: Text('系统', style: TextStyle(fontSize: 11.5)),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) {
              ref.read(uiServiceProvider).onThemeModeChanged(selection.first);
            }
          },
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            ),
          ),
        ),
      ],
    );
  }
}
