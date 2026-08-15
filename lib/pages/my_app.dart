import 'dart:io';
import 'dart:ui';

import 'package:asmr_downloader/pages/app_shell.dart';
import 'package:asmr_downloader/pages/components/initialization.dart';
import 'package:asmr_downloader/pages/window_title_bar/move_window.dart';
import 'package:asmr_downloader/pages/window_title_bar/window_title_bar.dart';
import 'package:asmr_downloader/pages/window_title_bar/window_close_handler.dart';
import 'package:asmr_downloader/services/ui/ui_service.dart';
import 'package:asmr_downloader/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Initialization(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: scaffoldMessengerKey,
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [
          Locale('en', 'US'), // English
          Locale('zh', 'CN'), // Chinese
        ],
        theme: AppTheme.dark(),
        scrollBehavior: MyCustomScrollBehavior(),
        home: Scaffold(
          // 背景色由深色主题的 scaffoldBackgroundColor 统一控制
          // Windows: MoveWindow 整窗可拖拽 + 自绘标题栏
          // macOS: 原生标题栏（红绿灯）自带拖拽，不需要 MoveWindow 和自绘标题栏
          body: WindowCloseHandler(
            child: Platform.isWindows
                ? MoveWindow(
                    child: Column(
                      children: [
                        WindowTitleBar(),
                        const Expanded(child: AppShell()),
                      ],
                    ),
                  )
                : const Column(
                    children: [
                      AppNavTabs(standalone: true),
                      Expanded(child: AppShell()),
                    ],
                  ),
          ),
        ),
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
