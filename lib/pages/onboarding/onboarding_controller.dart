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
      pageIndex: 0,
      targetKey: 'onboarding-search-box',
      title: '搜索作品',
      body: '输入 sourceId（RJ / VJ / BJ 开头加数字，如 RJ01234567）\n'
          '也可以直接粘贴 asmr.one 作品页 URL，自动提取 sourceId 与音轨目录。',
    ),
    _OnboardingStep(
      pageIndex: 0,
      targetKey: 'onboarding-paste-search',
      title: '快速搜索',
      body: '点这里读取剪贴板内容并自动搜索，无需手动粘贴。\n'
          '也支持直接把作品页链接拖拽到搜索框。',
    ),
    _OnboardingStep(
      pageIndex: 0,
      targetKey: 'onboarding-settings',
      title: '下载配置',
      body: '点这里打开下载设置：选择下载路径、下载线程数、代理、API 频道等。\n'
          '引导完成后可随时在这里重新查看本引导。',
    ),
    _OnboardingStep(
      pageIndex: 0,
      targetKey: 'onboarding-nav-tab-1',
      title: '切换页面',
      body: '点「作品库」标签切到文件管理页——整理作品、生成 AI 字幕、管理注册表。',
    ),
    _OnboardingStep(
      pageIndex: 1,
      targetKey: 'onboarding-navidrome-path',
      title: '整理到 Navidrome',
      body: '点文件夹图标选择 Navidrome 媒体库根目录。\n'
          '下载的作品会整理成媒体库结构（社团名 / RJ号 - CV - 标题 / 音轨），\n'
          '自动写入音频标签、获取封面、识别汉化版原版社团名。',
    ),
    _OnboardingStep(
      pageIndex: 1,
      targetKey: 'onboarding-install-engine',
      title: 'AI 字幕',
      body: '点「安装引擎」一键下载 ChickenRice 运行时与 Whisper 模型，\n'
          '装完自动配置，为没有字幕的音轨生成 AI 中文字幕。\n'
          '注意：AI 字幕仅支持 Windows；macOS 下相关控件会自动禁用。',
    ),
    _OnboardingStep(
      pageIndex: 1,
      targetKey: 'onboarding-organize-all',
      title: '批量操作',
      body: '点「整理全部」一次整理注册表内所有作品（或仅未整理的）。\n'
          '下方列表支持勾选多个作品后批量整理 / 生成字幕，\n'
          '也可逐行点行内图标整理或生成字幕。',
    ),
    _OnboardingStep(
      pageIndex: 1,
      targetKey: 'onboarding-nav-tab-2',
      title: '媒体库',
      body: '点「媒体库」标签切到第三页——缓存作品封面与信息、离线浏览。\n'
          '支持单作品缓存、批量缓存、补全缺失封面。',
    ),
    _OnboardingStep(
      pageIndex: 2,
      targetKey: 'onboarding-cache-management',
      title: '缓存管理',
      body: '点「缓存管理」管理已缓存作品：清空 / 导入 / 导出缓存数据库。\n'
          '旁边的「主动缓存」可按标签 / 社团 / CV 批量缓存作品元数据。',
    ),
    _OnboardingStep(
      pageIndex: 2,
      targetKey: 'onboarding-complete-missing',
      title: '补全缺失',
      body: '点「补全缺失」一键补全已缓存作品中缺失的封面与元数据信息。\n'
          '媒体库支持搜索、排序，离线浏览已缓存的作品卡片。',
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
    await _container.read(configFileProvider).addOrUpdate({'onboardingCompleted': true});
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

  /// 目标所在页面：0=下载, 1=作品库, 2=媒体库
  final int pageIndex;

  /// 目标元素的 ValueKey 字符串
  final String targetKey;

  final String title;
  final String body;
}
