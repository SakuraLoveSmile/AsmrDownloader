import 'dart:io';

import 'package:asmr_downloader/pages/my_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

Future<void> setupWindow(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  const initialSize = Size(1040, 690);
  await windowManager.ensureInitialized();

  if (Platform.isWindows) {
    WindowOptions windowOptions = const WindowOptions(
      size: initialSize,
      center: true,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Color(0xFF1E1E1E),
    );
    windowManager.waitUntilReadyToShow(windowOptions, () {
      windowManager
        ..setMinimumSize(initialSize)
        ..setTitle('AsmrDownloader')
        ..show()
        ..setPreventClose(true);
    });
  } else if (Platform.isMacOS) {
    // 使用原生标题栏（红绿灯按钮），无需自绘标题栏
    WindowOptions windowOptions = const WindowOptions(
      size: initialSize,
      center: true,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      backgroundColor: Color(0xFF1E1E1E),
    );
    windowManager.waitUntilReadyToShow(windowOptions, () {
      windowManager
        ..setMinimumSize(initialSize)
        ..setTitle('AsmrDownloader')
        ..show()
        ..setPreventClose(true);
    });
  }
}

void main(List<String> args) async {
  await setupWindow(args);
  runApp(const ProviderScope(child: MyApp()));
}
