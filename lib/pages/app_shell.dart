import 'package:asmr_downloader/pages/background_tasks/background_tasks.dart';
import 'package:asmr_downloader/pages/components/app_sidebar.dart';
import 'package:asmr_downloader/pages/database/database.dart';
import 'package:asmr_downloader/pages/downloader/downloader.dart';
import 'package:asmr_downloader/pages/downloader/download_list_page.dart';
import 'package:asmr_downloader/pages/library/library.dart';
import 'package:asmr_downloader/pages/media_library/media_library.dart';
import 'package:asmr_downloader/pages/update/update_banner.dart';
import 'package:asmr_downloader/pages/update/update_entry.dart';
import 'package:asmr_downloader/services/download/download_queue.dart';
import 'package:asmr_downloader/services/library/library_providers.dart';
import 'package:asmr_downloader/services/tasks/background_task_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 应用主导航页面索引，集中定义避免新增页面后散落的数字失效。
abstract final class AppPageIndex {
  static const downloader = 0;
  static const downloadList = 1;
  static const library = 2;
  static const mediaLibrary = 3;
  static const backgroundTasks = 4;
  static const database = 5;
}

/// 当前显示的页面，默认进入下载中心。
final currentPageProvider =
    StateProvider<int>((ref) => AppPageIndex.downloader);

/// 兼容旧代码别名
final currentNavTabProvider = currentPageProvider;

/// 应用外壳：采用现代 macOS 侧边栏 + 主工作区分栏架构。
///
/// 用 IndexedStack 保活六个页面——切页不销毁状态，
/// 下载进度、整理/字幕运行中的任务切到另一页也不被打断。
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(currentPageProvider);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 经典左侧边栏
        const AppSidebar(),
        // 主工作区
        Expanded(
          child: Column(
            children: [
              const UpdateBanner(),
              Expanded(
                child: IndexedStack(
                  index: index,
                  children: const [
                    Downloader(),
                    DownloadListPage(),
                    LibraryPage(),
                    MediaLibraryPage(),
                    BackgroundTasksPage(),
                    DatabasePage(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 顶部导航标签（可嵌入自绘标题栏，也可独立成行）。
class AppNavTabs extends ConsumerWidget {
  const AppNavTabs({super.key, this.standalone = false});

  /// 独立成行（macOS 无自绘标题栏时使用）：自带深色背景与高度。
  final bool standalone;

  static const _tabs = <(String, IconData)>[
    ('下载', Icons.arrow_downward_rounded),
    ('下载列表', Icons.playlist_play_rounded),
    ('作品库', Icons.folder_outlined),
    ('媒体库', Icons.photo_library_outlined),
    ('后台任务', Icons.task_alt_rounded),
    ('数据库', Icons.storage_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(currentPageProvider);
    final unorganized = ref.watch(unorganizedCountProvider).value ?? 0;
    final activeTasks = ref.watch(backgroundTaskActiveCountProvider);
    final currentDownloading = ref.watch(currentDownloadingSourceIdProvider);
    final queue = ref.watch(downloadQueueProvider);
    final downloadingCount =
        (currentDownloading != null ? 1 : 0) + queue.length;
    final scheme = Theme.of(context).colorScheme;

    // Segmented Pill 胶囊底座
    final tabs = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: scheme.outlineVariant, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _tabs.length; i++)
            _NavTab(
              key: ValueKey('onboarding-nav-tab-$i'),
              label: _tabs[i].$1,
              icon: _tabs[i].$2,
              selected: i == index,
              badgeCount: i == 1
                  ? downloadingCount
                  : i == 2
                      ? unorganized
                      : i == 4
                          ? activeTasks
                          : 0,
              onTap: () => ref.read(currentPageProvider.notifier).state = i,
            ),
        ],
      ),
    );

    if (!standalone) return tabs;
    return Container(
      width: double.infinity,
      height: 46,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 0.8),
        ),
      ),
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            tabs,
            const Spacer(),
            // 版本号 + 检查更新入口
            const UpdateEntry(),
          ],
        ),
      ),
    );
  }
}

class _NavTab extends StatefulWidget {
  const _NavTab({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  State<_NavTab> createState() => _NavTabState();
}

class _NavTabState extends State<_NavTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final color = selected ? scheme.onSurface : scheme.onSurfaceVariant;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? scheme.surfaceContainerHighest
                : _hovered
                    ? scheme.surfaceContainerHigh.withValues(alpha: 0.5)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: selected ? scheme.primary : color,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  letterSpacing: -0.1,
                ),
              ),
              if (widget.badgeCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '${widget.badgeCount}',
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
