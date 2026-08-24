import 'dart:io';

import 'package:asmr_downloader/pages/app_shell.dart';
import 'package:asmr_downloader/pages/downloader/search_box/search_box.dart';
import 'package:asmr_downloader/pages/my_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('快捷键 Cmd/Ctrl+1~6 支持快速切换主页面', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: AppGlobalShortcuts(
            child: Scaffold(
              body: SizedBox(width: 400, height: 400),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 默认在 downloader (0)
    expect(container.read(currentPageProvider), AppPageIndex.downloader);

    final modifier =
        Platform.isMacOS ? LogicalKeyboardKey.meta : LogicalKeyboardKey.control;

    // 按 Cmd/Ctrl + 2 -> downloadList (1)
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
    expect(container.read(currentPageProvider), AppPageIndex.downloadList);

    // 按 Cmd/Ctrl + 3 -> library (2)
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
    expect(container.read(currentPageProvider), AppPageIndex.library);

    // 按 Cmd/Ctrl + 4 -> mediaLibrary (3)
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
    expect(container.read(currentPageProvider), AppPageIndex.mediaLibrary);

    // 按 Cmd/Ctrl + 5 -> backgroundTasks (4)
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
    expect(container.read(currentPageProvider), AppPageIndex.backgroundTasks);

    // 按 Cmd/Ctrl + 6 -> database (5)
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit6);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
    expect(container.read(currentPageProvider), AppPageIndex.database);

    // 按 Cmd/Ctrl + 1 -> downloader (0)
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
    expect(container.read(currentPageProvider), AppPageIndex.downloader);
  });

  testWidgets('快捷键 Cmd/Ctrl+F 切换至下载页并聚焦搜索框', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // 先置为其他页面
    container.read(currentPageProvider.notifier).state = AppPageIndex.library;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: AppGlobalShortcuts(
            child: Scaffold(
              body: Column(
                children: [
                  TextField(
                    focusNode: searchBoxFocusNode,
                    key: const ValueKey('test-search-field'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(searchBoxFocusNode.hasFocus, isFalse);

    final modifier =
        Platform.isMacOS ? LogicalKeyboardKey.meta : LogicalKeyboardKey.control;

    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();

    expect(container.read(currentPageProvider), AppPageIndex.downloader);
    expect(searchBoxFocusNode.hasFocus, isTrue);
  });
}
