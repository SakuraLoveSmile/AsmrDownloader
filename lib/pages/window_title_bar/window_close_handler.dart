import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

/// 全局监听窗口关闭事件，下载中关闭时弹出确认对话框。
/// Windows 的自绘关闭按钮和 macOS 的原生红绿灯都会触发 onWindowClose。
class WindowCloseHandler extends ConsumerStatefulWidget {
  const WindowCloseHandler({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WindowCloseHandler> createState() => _WindowCloseHandlerState();
}

class _WindowCloseHandlerState extends ConsumerState<WindowCloseHandler>
    with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    ref.read(uiServiceProvider).onExit(context);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
