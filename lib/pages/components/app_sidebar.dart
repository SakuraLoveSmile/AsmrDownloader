import 'dart:io';

import 'package:asmr_downloader/pages/app_shell.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/log_viewer_button.dart';
import 'package:asmr_downloader/pages/downloader/settings_panel.dart';
import 'package:asmr_downloader/pages/update/update_entry.dart';
import 'package:asmr_downloader/services/cache/cache_library_providers.dart';
import 'package:asmr_downloader/services/download/download_queue.dart';
import 'package:asmr_downloader/services/library/library_providers.dart';
import 'package:asmr_downloader/services/tasks/background_task_service.dart';
import 'package:asmr_downloader/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// macOS / 现代桌面端经典左侧边栏 (Sidebar)。
class AppSidebar extends ConsumerWidget {
  const AppSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final currentIndex = ref.watch(currentPageProvider);

    // 动态徽标统计
    final currentDownloading = ref.watch(currentDownloadingSourceIdProvider);
    final queue = ref.watch(downloadQueueProvider);
    final downloadingCount = (currentDownloading != null ? 1 : 0) + queue.length;

    final unorganized = ref.watch(unorganizedCountProvider).value ?? 0;
    final cachedCount = ref.watch(cachedLibraryProvider).value?.entries.length ?? 0;
    final activeTasks = ref.watch(backgroundTaskActiveCountProvider);

    return Container(
      width: 210,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: scheme.outlineVariant, width: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // macOS 下为系统红绿灯留出安全边距
          if (Platform.isMacOS) const SizedBox(height: 38) else const SizedBox(height: 14),
          // 顶部品牌区
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.headphones_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'ASMR Downloader',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Divider(height: 1),
          ),
          const SizedBox(height: 12),
          // 主导航列表
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              key: const ValueKey('onboarding-sidebar-nav'),
              children: [
                _SidebarItem(
                  key: const ValueKey('onboarding-sidebar-download'),
                  index: 0,
                  currentIndex: currentIndex,
                  icon: Icons.arrow_circle_down_rounded,
                  label: '下载中心',
                  badgeText: downloadingCount > 0 ? '$downloadingCount' : null,
                  badgeColor: scheme.primary,
                  onTap: () => ref.read(currentPageProvider.notifier).state = 0,
                ),
                const SizedBox(height: 4),
                _SidebarItem(
                  key: const ValueKey('onboarding-sidebar-library'),
                  index: 1,
                  currentIndex: currentIndex,
                  icon: Icons.folder_copy_rounded,
                  label: '作品库',
                  badgeText: unorganized > 0 ? '$unorganized' : null,
                  badgeColor: AppColors.warningSolid,
                  onTap: () => ref.read(currentPageProvider.notifier).state = 1,
                ),
                const SizedBox(height: 4),
                _SidebarItem(
                  key: const ValueKey('onboarding-sidebar-media'),
                  index: 2,
                  currentIndex: currentIndex,
                  icon: Icons.photo_library_rounded,
                  label: '媒体库',
                  badgeText: cachedCount > 0 ? '$cachedCount' : null,
                  badgeColor: scheme.surfaceContainerHighest,
                  badgeTextColor: scheme.onSurfaceVariant,
                  onTap: () => ref.read(currentPageProvider.notifier).state = 2,
                ),
                const SizedBox(height: 4),
                _SidebarItem(
                  key: const ValueKey('onboarding-sidebar-tasks'),
                  index: 3,
                  currentIndex: currentIndex,
                  icon: Icons.task_alt_rounded,
                  label: '后台任务',
                  badgeText: activeTasks > 0 ? '$activeTasks' : null,
                  badgeColor: scheme.primary,
                  onTap: () => ref.read(currentPageProvider.notifier).state = 3,
                ),
              ],
            ),
          ),
          const Spacer(),
          // 底部工具与系统区
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Divider(height: 1),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              children: [
                // 设置与日志快捷按钮
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => const DownloaderSettingsPanel(),
                        ),
                        icon: const Icon(Icons.settings_outlined, size: 15),
                        label: const Text('偏好设置', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                    const LogViewerButton(),
                  ],
                ),
                const SizedBox(height: 4),
                // 版本号与更新检查
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: UpdateEntry(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    super.key,
    required this.index,
    required this.currentIndex,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badgeText,
    this.badgeColor,
    this.badgeTextColor,
  });

  final int index;
  final int currentIndex;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badgeText;
  final Color? badgeColor;
  final Color? badgeTextColor;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = widget.index == widget.currentIndex;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? scheme.primary.withValues(alpha: 0.14)
                : _hovered
                    ? scheme.surfaceContainerHigh.withValues(alpha: 0.5)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 17,
                color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: isSelected ? scheme.primary : scheme.onSurface,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 13,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              if (widget.badgeText != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: widget.badgeColor ?? scheme.primary,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    widget.badgeText!,
                    style: TextStyle(
                      color: widget.badgeTextColor ?? scheme.onPrimary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
