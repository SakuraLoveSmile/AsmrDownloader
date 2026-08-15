import 'package:flutter/material.dart';

/// 全局语义色：状态色与文件类型图标色，替代散落的 Colors.xxxAccent。
/// 状态色按深色主题设计：浅字 + 深底，用于 chip / 状态标签。
abstract final class AppColors {
  // 状态色（深底 + 亮字，用于 chip / 状态标签）
  static const success = Color(0xFF7ED49A);
  static const successBg = Color(0xFF1D3B2A);
  static const warning = Color(0xFFE8A33D);
  static const warningBg = Color(0xFF3A2C10);
  static const info = Color(0xFF8AB4F8);
  static const infoBg = Color(0xFF1D2E47);
  static const danger = Color(0xFFF28B82);
  static const dangerBg = Color(0xFF41221F);

  /// 重试按钮等实心场景的警告色（配白字）
  static const warningSolid = Color(0xFFED6C02);

  // 文件类型图标色
  static const folder = Color(0xFFF9C100);
  static const audio = Color(0xFF64B5F6);
  static const image = Color(0xFF81C784);
  static const textFile = Color(0xFF9E9E9E);

  // CV 标签配色（深底 + 亮青字）
  static const cvBg = Color(0xFF123B36);
  static const cvText = Color(0xFF6FD6C6);
}

/// 应用深色主题：沉浸式深色风格。
///
/// 所有页面组件应通过 Theme / ColorScheme 取色，禁止再硬编码颜色。
abstract final class AppTheme {
  static const _seed = Color(0xFF7C4DFF);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    ).copyWith(
      surface: const Color(0xFF1E1E1E),
    );

    final outlineBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,

      // ---------- 输入框 ----------
      inputDecorationTheme: InputDecorationThemeData(
        isDense: true,
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        hintStyle:
            TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.65)),
        border: outlineBorder,
        enabledBorder: outlineBorder,
        disabledBorder: outlineBorder.copyWith(
          borderSide: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.error, width: 1.4),
        ),
      ),

      // ---------- 按钮 ----------
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          textStyle: const TextStyle(fontSize: 12),
          side: BorderSide(color: scheme.outlineVariant),
          foregroundColor: scheme.onSurface.withValues(alpha: 0.85),
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          textStyle: const TextStyle(fontSize: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontSize: 13),
        ),
      ),

      // ---------- 下拉菜单 ----------
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationThemeData(
          isDense: true,
          filled: true,
          fillColor: scheme.surfaceContainerLow,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: outlineBorder,
          enabledBorder: outlineBorder,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: scheme.primary, width: 1.4),
          ),
        ),
        textStyle: TextStyle(fontSize: 13, color: scheme.onSurface),
        menuStyle: MenuStyle(
          backgroundColor:
              WidgetStatePropertyAll(scheme.surfaceContainer),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          elevation: const WidgetStatePropertyAll(4),
        ),
      ),

      // ---------- 选择控件 ----------
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? scheme.primary
                : Colors.transparent),
        checkColor: WidgetStatePropertyAll(scheme.onPrimary),
        side: BorderSide(color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
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
        thickness: 1,
      ),

      // ---------- 进度 / 提示 ----------
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        linearMinHeight: 6,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }
}
