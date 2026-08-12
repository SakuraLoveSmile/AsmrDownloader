import 'dart:io';
import 'dart:ui';

import 'package:asmr_downloader/pages/components/initialization.dart';
import 'package:asmr_downloader/pages/downloader/downloader.dart';
import 'package:asmr_downloader/pages/window_title_bar/move_window.dart';
import 'package:asmr_downloader/pages/window_title_bar/window_title_bar.dart';
import 'package:asmr_downloader/pages/window_title_bar/window_close_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Initialization(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [
          Locale('en', 'US'), // English
          Locale('zh', 'CN'), // Chinese
        ],
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.purple,
            dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
            brightness: Brightness.dark,
          ),
        ),
        scrollBehavior: MyCustomScrollBehavior(),
        home: Scaffold(
          // Windows 透明背景配合 acrylic 窗口效果；macOS 使用不透明深色背景
          backgroundColor: Platform.isWindows
              ? Colors.transparent
              : const Color(0xFF1E1E1E),
          // Windows: MoveWindow 整窗可拖拽 + 自绘标题栏
          // macOS: 原生标题栏（红绿灯）自带拖拽，不需要 MoveWindow 和自绘标题栏
          body: WindowCloseHandler(
            child: Platform.isWindows
                ? MoveWindow(
                    child: Column(
                      children: [
                        WindowTitleBar(),
                        const Downloader(),
                      ],
                    ),
                  )
                : const Column(
                    children: [
                      Downloader(),
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
