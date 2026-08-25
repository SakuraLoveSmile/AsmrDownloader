import 'package:asmr_downloader/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSemanticColors', () {
    test('暗色与浅色语义颜色定义完整', () {
      final dark = AppSemanticColors.dark();
      final light = AppSemanticColors.light();

      expect(dark.surfaceSubtle, isNotNull);
      expect(dark.surfaceHover, isNotNull);
      expect(dark.tagBg, isNotNull);
      expect(dark.tagBorder, isNotNull);
      expect(dark.glassBg, isNotNull);
      expect(dark.glassBorder, isNotNull);
      expect(dark.divider, isNotNull);

      expect(light.surfaceSubtle, isNotNull);
      expect(light.surfaceHover, isNotNull);
      expect(light.tagBg, isNotNull);
      expect(light.tagBorder, isNotNull);
      expect(light.glassBg, isNotNull);
      expect(light.glassBorder, isNotNull);
      expect(light.divider, isNotNull);

      expect(dark.surfaceSubtle, isNot(equals(light.surfaceSubtle)));
    });

    test('支持 lerp 平滑插值与 copyWith', () {
      final dark = AppSemanticColors.dark();
      final light = AppSemanticColors.light();

      final lerped = dark.lerp(light, 0.5);
      expect(lerped.surfaceSubtle,
          Color.lerp(dark.surfaceSubtle, light.surfaceSubtle, 0.5));

      final copied = dark.copyWith(surfaceSubtle: const Color(0xFF123456));
      expect(copied.surfaceSubtle, const Color(0xFF123456));
      expect(copied.surfaceHover, dark.surfaceHover);
    });
  });

  group('AppTheme', () {
    test('深色主题包含 AppSemanticColors 扩展且配置正确', () {
      final theme = AppTheme.dark();
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.brightness, Brightness.dark);
      expect(theme.extension<AppSemanticColors>(), isNotNull);
      expect(theme.extension<AppSemanticColors>()!.surfaceSubtle,
          const Color(0xFF1E1E1E));
    });

    test('浅色主题包含 AppSemanticColors 扩展且配置正确', () {
      final theme = AppTheme.light();
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.brightness, Brightness.light);
      expect(theme.extension<AppSemanticColors>(), isNotNull);
      expect(theme.extension<AppSemanticColors>()!.surfaceSubtle,
          const Color(0xFFF2F2F7));
    });
  });
}
