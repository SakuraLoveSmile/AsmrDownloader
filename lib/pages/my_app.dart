import 'dart:io';
import 'dart:ui';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/pages/app_shell.dart';
import 'package:asmr_downloader/pages/components/initialization.dart';
import 'package:asmr_downloader/pages/downloader/search_box/search_box.dart';
import 'package:asmr_downloader/pages/window_title_bar/move_window.dart';
import 'package:asmr_downloader/pages/window_title_bar/window_title_bar.dart';
import 'package:asmr_downloader/pages/window_title_bar/window_close_handler.dart';
import 'package:asmr_downloader/services/ui/ui_service.dart';
import 'package:asmr_downloader/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeModeStr = ref.watch(themeModeProvider);
    final themeMode = switch (themeModeStr) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };

    return Initialization(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: scaffoldMessengerKey,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en', 'US'), // English
          Locale('zh', 'CN'), // Chinese
        ],
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        scrollBehavior: MyCustomScrollBehavior(),
        home: AppGlobalShortcuts(
          child: Scaffold(
            // 背景色由主题的 scaffoldBackgroundColor 统一控制
            // Windows: MoveWindow 整窗可拖拽 + 自绘标题栏
            // macOS: 原生标题栏（红绿灯）自带拖拽，不需要 MoveWindow 和自绘标题栏
            body: WindowCloseHandler(
              child: Platform.isWindows
                  ? MoveWindow(
                      child: Column(
                        children: [
                          WindowTitleBar(),
                          Expanded(child: AppShell()),
                        ],
                      ),
                    )
                  : AppShell(),
            ),
          ),
        ),
      ),
    );
  }
}

/// 全局键盘快捷键响应器：支持 Cmd/Ctrl+F 搜索聚焦与 Cmd/Ctrl+1~6 切页。
class AppGlobalShortcuts extends ConsumerWidget {
  const AppGlobalShortcuts({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMac = Platform.isMacOS;

    SingleActivator activator(LogicalKeyboardKey key) {
      return SingleActivator(
        key,
        meta: isMac,
        control: !isMac,
      );
    }

    return CallbackShortcuts(
      bindings: {
        activator(LogicalKeyboardKey.keyF): () {
          ref.read(currentPageProvider.notifier).state =
              AppPageIndex.downloader;
          searchBoxFocusNode.requestFocus();
        },
        activator(LogicalKeyboardKey.digit1): () {
          ref.read(currentPageProvider.notifier).state =
              AppPageIndex.downloader;
        },
        activator(LogicalKeyboardKey.digit2): () {
          ref.read(currentPageProvider.notifier).state =
              AppPageIndex.downloadList;
        },
        activator(LogicalKeyboardKey.digit3): () {
          ref.read(currentPageProvider.notifier).state =
              AppPageIndex.library;
        },
        activator(LogicalKeyboardKey.digit4): () {
          ref.read(currentPageProvider.notifier).state =
              AppPageIndex.mediaLibrary;
        },
        activator(LogicalKeyboardKey.digit5): () {
          ref.read(currentPageProvider.notifier).state =
              AppPageIndex.backgroundTasks;
        },
        activator(LogicalKeyboardKey.digit6): () {
          ref.read(currentPageProvider.notifier).state =
              AppPageIndex.database;
        },
      },
      child: Focus(
        autofocus: true,
        child: child,
      ),
    );
  }
}

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  // Override behavior methods and getters like dragDevices
  @override
  Set<PointerDeviceKind> get dragDevices => {
        // default
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        // enable mouse && trackpad
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad
      };
}
