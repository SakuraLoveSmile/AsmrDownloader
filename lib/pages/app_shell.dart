import 'package:asmr_downloader/pages/downloader/downloader.dart';
import 'package:asmr_downloader/pages/library/library.dart';
import 'package:asmr_downloader/services/library/library_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 当前显示的页面：0 = 下载，1 = 作品库
final currentPageProvider = StateProvider<int>((ref) => 0);

/// 应用外壳：下载 / 作品库双页面。
///
/// 用 IndexedStack 保活两个页面——切页不销毁状态，
/// 下载进度、整理/字幕运行中的任务切到另一页也不被打断。
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(currentPageProvider);
    return IndexedStack(
      index: index,
      children: const [
        Downloader(),
        LibraryPage(),
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
    ('下载', Icons.download_outlined),
    ('作品库', Icons.folder_outlined),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(currentPageProvider);
    final unorganized = ref.watch(unorganizedCountProvider).value ?? 0;
    final tabs = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _tabs.length; i++)
          _NavTab(
            label: _tabs[i].$1,
            icon: _tabs[i].$2,
            selected: i == index,
            badgeCount: i == 1 ? unorganized : 0,
            onTap: () => ref.read(currentPageProvider.notifier).state = i,
          ),
      ],
    );
    if (!standalone) return tabs;
    return Container(
      width: double.infinity,
      height: 40,
      color: const Color(0xFF1E1E1E),
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: tabs,
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
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

  /// 右上角徽标数字（0 不显示）
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : Colors.white60;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: selected ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (badgeCount > 0) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade700,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$badgeCount',
                      style: const TextStyle(
                          color: Colors.black, fontSize: 10),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
