import 'package:asmr_downloader/pages/background_tasks/background_tasks.dart';
import 'package:asmr_downloader/pages/components/app_sidebar.dart';
import 'package:asmr_downloader/pages/database/database.dart';
import 'package:asmr_downloader/pages/downloader/downloader.dart';
import 'package:asmr_downloader/pages/downloader/download_list_page.dart';
import 'package:asmr_downloader/pages/library/library.dart';
import 'package:asmr_downloader/pages/media_library/media_library.dart';
import 'package:asmr_downloader/pages/update/update_banner.dart';
import 'package:asmr_downloader/services/download/download_queue.dart';
import 'package:asmr_downloader/services/tasks/background_task_service.dart';
import 'package:asmr_downloader/services/transcribe/transcribe_providers.dart';
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
                child: Stack(
                  children: [
                    IndexedStack(
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
                    const Positioned(
                      right: 18,
                      bottom: 16,
                      child: _GlobalTaskPill(),
                    ),
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

/// 全局任务指示浮条：当有正在进行的下载、AI字幕或后台任务时在右下角悬浮提示，点击直达对应页面。
class _GlobalTaskPill extends ConsumerWidget {
  const _GlobalTaskPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadingSourceId = ref.watch(currentDownloadingSourceIdProvider);
    final isDownloading = downloadingSourceId != null;
    final isTranscribing = ref.watch(activeTranscribeSourceIdProvider) != null;
    final tasks = ref.watch(backgroundTaskProvider);
    final activeTasks = tasks
        .where((t) =>
            t.status == BackgroundTaskStatus.running ||
            t.status == BackgroundTaskStatus.queued)
        .length;

    if (!isDownloading && !isTranscribing && activeTasks == 0) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;

    String label;
    if (isDownloading && activeTasks > 0) {
      label = '下载中 · $activeTasks 个后台任务';
    } else if (isDownloading) {
      label = '正在下载 $downloadingSourceId';
    } else if (isTranscribing) {
      label = '正在生成 AI 字幕';
    } else {
      label = '$activeTasks 个后台任务运行中';
    }

    return Material(
      key: const ValueKey('global-task-pill'),
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (activeTasks > 0) {
            ref.read(currentPageProvider.notifier).state =
                AppPageIndex.backgroundTasks;
          } else {
            ref.read(currentPageProvider.notifier).state =
                AppPageIndex.downloadList;
          }
        },
        borderRadius: BorderRadius.circular(100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: scheme.primary.withValues(alpha: 0.35),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
