import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/pages/app_shell.dart';
import 'package:asmr_downloader/pages/onboarding/onboarding_overlay.dart';
import 'package:asmr_downloader/services/ui/ui_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 启动交互式新手引导。
///
/// 通过根 Navigator 的 overlay 注入全屏高亮层。可从 [initialization.dart]
/// 首次启动自动触发，也可从设置面板的「新手引导」按钮手动触发。
void startOnboarding(ProviderContainer container) {
  OnboardingController(container).start();
}

/// 交互式新手引导控制器：10 步高亮真实 UI 元素 + 气泡说明。
///
/// 每步先切到目标页面（IndexedStack 保活），等一帧后定位元素 Rect，
/// 重建 overlay 显示遮罩 + 气泡。完成或跳过写 onboardingCompleted 并移除 overlay。
class OnboardingController {
  OnboardingController(this._container);

  final ProviderContainer _container;
  OverlayEntry? _entry;
  int _step = 0;

  static const _steps = <_OnboardingStep>[
    _OnboardingStep(
      pageIndex: AppPageIndex.downloader,
      targetKey: 'onboarding-sidebar-nav',
      title: '全新经典侧边栏',
      body: '左侧边栏整合了「下载中心」、「下载列表」、「作品库」、「媒体库」、「后台任务」与「数据库」六大主模块。\n'
          '边栏会实时显示活动下载任务数、未整理作品数和后台任务数等动态徽标，助你随时掌握后台状态。',
    ),
    _OnboardingStep(
      pageIndex: AppPageIndex.downloader,
      targetKey: 'onboarding-search-box',
      title: '智能搜索与解析',
      body: '输入 sourceId（RJ / VJ / BJ 加数字，如 RJ01234567）\n'
          '也可以直接粘贴 asmr.one 作品页 URL，或拖入链接与文件，自动提取作品信息与完整音轨目录。',
    ),
    _OnboardingStep(
      pageIndex: AppPageIndex.downloader,
      targetKey: 'onboarding-paste-search',
      title: '一键剪贴板搜索',
      body: '点击快速读取系统剪贴板并立即发起搜索与解析。\n'
          '旁边的刷新按钮支持在网络或元数据更新时一键强制刷新缓存。',
    ),
    _OnboardingStep(
      pageIndex: AppPageIndex.downloader,
      targetKey: 'onboarding-settings',
      title: '下载与网络偏好',
      body: '点击打开下载设置弹窗：配置下载目录、多线程并行数、API 镜像通道、网络代理与 GitHub Token。',
    ),
    _OnboardingStep(
      pageIndex: AppPageIndex.downloadList,
      targetKey: 'onboarding-sidebar-download-list',
      title: '独立下载列表',
      body: '下载列表单独展示当前与最近一次下载的逐文件进度、速度、状态和作品队列。下载过程中切换页面，任务不会中断。',
    ),
    _OnboardingStep(
      pageIndex: AppPageIndex.library,
      targetKey: 'onboarding-sidebar-library',
      title: '已下载作品库',
      body: '点击侧边栏「作品库」进入已下载作品管理中心，支持多选、分类筛选与元数据整理。',
    ),
    _OnboardingStep(
      pageIndex: AppPageIndex.library,
      targetKey: 'onboarding-library-toolbar',
      title: '智能整理与 AI 字幕',
      body: '支持一键整理到 Navidrome 媒体库（自动写入音频 ID3 标签、封面、汉化版社团解析）。\n'
          '支持调用 ChickenRice (Faster-Whisper) 自动生成 AI 中文字幕。\n'
          '点击工具栏右侧的设置按钮可配置目标媒体库路径与 AI 引擎。',
    ),
    _OnboardingStep(
      pageIndex: AppPageIndex.mediaLibrary,
      targetKey: 'onboarding-sidebar-media',
      title: '离线媒体库',
      body: '点击侧边栏「媒体库」进入封面海报瀑布流，支持离线高速浏览全部已缓存作品。',
    ),
    _OnboardingStep(
      pageIndex: AppPageIndex.mediaLibrary,
      targetKey: 'onboarding-media-toolbar',
      title: '海报浏览与详情检查器',
      body: '顶部工具栏支持关键词搜索、排序与一键批量缓存。\n'
          '💡 技巧：点击任意作品海报，右侧将滑出非模态详情检查器（Inspector），点击声优或标签即可即时联动过滤！',
    ),
  ];

  void start() {
    _step = 0;
    _showStep();
  }

  void _next() {
    if (_step < _steps.length - 1) {
      _step++;
      _showStep();
    } else {
      _finish();
    }
  }

  void _prev() {
    if (_step > 0) {
      _step--;
      _showStep();
    }
  }

  void _skip() => _finish();

  Future<void> _finish() async {
    _entry?.remove();
    _entry = null;
    await _container
        .read(configFileProvider)
        .addOrUpdate({'onboardingCompleted': true});
    _container.read(onboardingCompletedProvider.notifier).state = true;
  }

  void _showStep() {
    final step = _steps[_step];

    // 切到目标页面（IndexedStack 保活，元素已挂载）
    _container.read(currentPageProvider.notifier).state = step.pageIndex;

    // 等一帧让页面切换生效后定位元素
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rect = _locateTarget(step.targetKey);
      _renderStep(rect);
    });
  }

  /// 通过 ValueKey 在 widget 树中查找目标元素的屏幕坐标 Rect。
  Rect _locateTarget(String keyString) {
    final navState = navigatorKey.currentState;
    if (navState == null || !navState.mounted) return Rect.zero;

    final context = navState.context;
    final key = ValueKey(keyString);
    final result = _findRenderObjectByKey(context, key);
    if (result is! RenderBox) return Rect.zero;

    final translation = result.localToGlobal(Offset.zero);
    return translation & result.size;
  }

  /// 递归查找 widget 树中匹配指定 Key 的 RenderObject。
  RenderObject? _findRenderObjectByKey(BuildContext context, Key key) {
    RenderObject? found;
    void visitor(Element element) {
      if (found != null) return;
      if (element.widget.key == key) {
        found = element.findRenderObject();
        return;
      }
      element.visitChildElements(visitor);
    }

    context.visitChildElements(visitor);
    return found;
  }

  void _renderStep(Rect targetRect) {
    _entry?.remove();
    _entry = OverlayEntry(
      builder: (_) => OnboardingOverlay(
        step: _step,
        stepCount: _steps.length,
        title: _steps[_step].title,
        body: _steps[_step].body,
        targetRect: targetRect,
        onNext: _next,
        onPrev: _prev,
        onSkip: _skip,
      ),
    );

    final navState = navigatorKey.currentState;
    if (navState != null && navState.mounted) {
      navState.overlay?.insert(_entry!);
    }
  }
}

class _OnboardingStep {
  const _OnboardingStep({
    required this.pageIndex,
    required this.targetKey,
    required this.title,
    required this.body,
  });

  /// 目标所在页面：由 [AppPageIndex] 定义。
  final int pageIndex;

  /// 目标元素的 ValueKey 字符串
  final String targetKey;

  final String title;
  final String body;
}
