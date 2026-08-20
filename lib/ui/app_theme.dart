import 'package:flutter/material.dart';

/// 全局语义色：贴合 Apple Human Interface Guidelines (HIG) 标准系统色。
/// 深色模式下采用高对比度前景色与半透明高雅背景。
abstract final class AppColors {
  // Apple System Colors (Dark Mode)
  static const brandBlue = Color(0xFF0A84FF);
  static const brandBlueHover = Color(0xFF0071E3);

  // 状态色（Apple Dark Functional Colors）
  static const success = Color(0xFF30D158);
  static const successBg = Color(0x2630D158); // ~15% 透明绿
  static const warning = Color(0xFFFF9F0A);
  static const warningBg = Color(0x26FF9F0A); // ~15% 透明橙
  static const info = Color(0xFF0A84FF);
  static const infoBg = Color(0x260A84FF); // ~15% 透明蓝
  static const danger = Color(0xFFFF453A);
  static const dangerBg = Color(0x26FF453A); // ~15% 透明红

  /// 实心按钮/显著告警场景
  static const warningSolid = Color(0xFFFF9F0A);
  static const dangerSolid = Color(0xFFFF453A);

  // 文件类型图标色 (Apple System Colors)
  static const folder = Color(0xFFFFD60A); // Apple Yellow
  static const audio = Color(0xFF0A84FF);  // Apple Music Blue
  static const image = Color(0xFF30D158);  // Apple Photos Green
  static const textFile = Color(0xFF8E8E93); // Apple System Gray

  // CV 标签配色（Apple Cyan 晶莹半透明）
  static const cvBg = Color(0x2664D2FF);
  static const cvText = Color(0xFF64D2FF);

  // 细边框与分割线
  static const hairline = Color(0x1FFFFFFF); // 12% 白
  static const subtleHover = Color(0x14FFFFFF); // 8% 白
}

/// 应用深色主题：沉浸式 Apple 设计风格。
abstract final class AppTheme {
  static const _primarySeed = Color(0xFF0A84FF);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _primarySeed,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.brandBlue,
      onPrimary: Colors.white,
      primaryContainer: const Color(0x260A84FF),
      onPrimaryContainer: const Color(0xFF70B4FF),
      surface: const Color(0xFF0F0F12), // Deep Space Black / Scaffold
      surfaceContainerLowest: const Color(0xFF141417),
      surfaceContainerLow: const Color(0xFF1C1C1E), // Apple Grouped Background
      surfaceContainer: const Color(0xFF242428),
      surfaceContainerHigh: const Color(0xFF2C2C2E), // Apple Card Background
      surfaceContainerHighest: const Color(0xFF3A3A3E), // Hover & High Contrast
      onSurface: const Color(0xFFF5F5F7), // Apple Primary Text
      onSurfaceVariant: const Color(0xFF8E8E93), // Apple Secondary Text
      outline: const Color(0x388E8E93),
      outlineVariant: AppColors.hairline,
      error: AppColors.danger,
      onError: Colors.white,
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: scheme.outlineVariant, width: 0.8),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      fontFamilyFallback: const [
        '-apple-system',
        'BlinkMacSystemFont',
        'SF Pro Text',
        'SF Pro Display',
        'PingFang SC',
        'Hiragino Sans GB',
        'Microsoft YaHei',
        'sans-serif',
      ],

      // ---------- 输入框 ----------
      inputDecorationTheme: InputDecorationThemeData(
        isDense: true,
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
          fontSize: 13,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        disabledBorder: inputBorder.copyWith(
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
            width: 0.8,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.primary, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.error, width: 1.0),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.error, width: 1.4),
        ),
      ),

      // ---------- 按钮（全胶囊 Stadium 风格） ----------
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          side: BorderSide(color: scheme.outlineVariant, width: 0.8),
          foregroundColor: scheme.onSurface.withValues(alpha: 0.9),
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.3),
          backgroundColor: scheme.surfaceContainerLow.withValues(alpha: 0.5),
          shape: const StadiumBorder(),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: const StadiumBorder(),
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
      ),

      // ---------- 下拉菜单 ----------
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationThemeData(
          isDense: true,
          filled: true,
          fillColor: scheme.surfaceContainerLow,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: inputBorder,
          enabledBorder: inputBorder,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: scheme.primary, width: 1.2),
          ),
        ),
        textStyle: TextStyle(fontSize: 13, color: scheme.onSurface),
        menuStyle: MenuStyle(
          backgroundColor:
              WidgetStatePropertyAll(scheme.surfaceContainerHigh),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.outlineVariant, width: 0.8),
            ),
          ),
          elevation: const WidgetStatePropertyAll(6),
        ),
      ),

      // ---------- 选择控件 ----------
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? scheme.primary
                : Colors.transparent),
        checkColor: WidgetStatePropertyAll(scheme.onPrimary),
        side: BorderSide(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.65),
          width: 1.2,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),

      // ---------- 列表 / 折叠 ----------
      expansionTileTheme: ExpansionTileThemeData(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        textColor: scheme.onSurface,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 0.8,
        space: 1,
      ),

      // ---------- 进度 / 提示 ----------
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        linearMinHeight: 6,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(color: scheme.onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant, width: 0.8),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant, width: 0.8),
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant, width: 0.8),
        ),
      ),
    );
  }
}
