import 'package:asmr_downloader/pages/components/copyable_textbox.dart';
import 'package:asmr_downloader/pages/downloader/search_result/work_info/components/asmr_cv.dart';
import 'package:asmr_downloader/pages/downloader/search_result/work_info/components/asmr_library_status.dart';
import 'package:asmr_downloader/pages/downloader/search_result/work_info/components/asmr_misc_info.dart';
import 'package:asmr_downloader/pages/downloader/search_result/work_info/components/asmr_tags.dart';
import 'package:asmr_downloader/pages/downloader/search_result/work_info/components/asmr_circle_name.dart';
import 'package:asmr_downloader/pages/downloader/search_result/work_info/components/asmr_cover.dart';
import 'package:asmr_downloader/pages/downloader/search_result/work_info/components/asmr_title.dart';
import 'package:asmr_downloader/pages/window_title_bar/move_window.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/tracks_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/work_info_providers.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkInfo extends ConsumerWidget {
  const WorkInfo({super.key, this.horizontalPadding = 12.0});
  final double horizontalPadding;

  static const _verticalPadding = 10.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workInfoLoadingState = ref.watch(workInfoLoadingStateProvider);
    return Padding(
      padding:
          EdgeInsets.only(left: horizontalPadding, right: horizontalPadding),
      child: workInfoLoadingState.when(
        data: (data) {
          if (data == null) {
            // 搜索了但拿不到 work info：
            // 无 sourceId 说明搜索结果为空；否则进入降级模式
            if (ref.read(sourceIdProvider) == null) {
              return _buildNotFound(context);
            }
            return _buildFallbackInfo(context, ref);
          }
          return MoveWindow(
            moveOnChildWidget: true,
            child: ScrollConfiguration(
              behavior:
                  ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AsmrCover(),
                    AsmrLibraryStatus(verticalPadding: _verticalPadding),
                    AsmrTitle(verticalPadding: _verticalPadding),
                    AsmrCircleName(verticalPadding: _verticalPadding),
                    AsmrMiscInfo(verticalPadding: _verticalPadding),
                    AsmrTags(verticalPadding: _verticalPadding),
                    AsmrCv(verticalPadding: _verticalPadding),
                  ],
                ),
              ),
            ),
          );
        },
        loading: () => Center(child: const CircularProgressIndicator()),
        error: (error, stack) => _buildErrorRetry(context, ref, error),
      ),
    );
  }

  /// 加载失败：错误提示 + 重试按钮（保留降级信息）
  Widget _buildErrorRetry(BuildContext context, WidgetRef ref, Object error) {
    final sourceId = ref.watch(sourceIdProvider);
    return MoveWindow(
      moveOnChildWidget: true,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '加载失败：$error',
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => ref
                      ..invalidate(searchResultProvider)
                      ..invalidate(workInfoProvider)
                      ..invalidate(rawTracksProvider)
                      ..invalidate(coverBytesProvider),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('重试'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (sourceId != null) _buildFallbackInfoContent(context, ref),
            ],
          ),
        ),
      ),
    );
  }

  /// 搜索结果为空（查无此作品）
  Widget _buildNotFound(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off,
              size: 48, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
          SizedBox(height: 12),
          Text(
            '未找到匹配的作品\n请检查 sourceId 或网络后重试',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// 降级模式：work info 获取失败时展示的保底信息区
  Widget _buildFallbackInfo(BuildContext context, WidgetRef ref) {
    return MoveWindow(
      moveOnChildWidget: true,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          child: _buildFallbackInfoContent(context, ref),
        ),
      ),
    );
  }

  /// 降级信息内容（供独立展示与错误重试区复用，避免嵌套滚动视图）
  Widget _buildFallbackInfoContent(BuildContext context, WidgetRef ref) {
    final sourceId = ref.watch(sourceIdProvider) ?? '';
    final fallbackTitle = ref.watch(titleProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '作品信息获取失败，已使用降级标签',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        const SizedBox(height: 12),
        CopyableTextBox(
          text: fallbackTitle,
          textStyle: Theme.of(context).textTheme.bodyLarge,
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        CopyableTextBox(
          text: sourceId,
          textStyle: Theme.of(context).textTheme.bodyMedium,
          padding: EdgeInsets.zero,
        ),
        // 降级模式下同样展示入库状态（检测只依赖 sourceId）
        AsmrLibraryStatus(verticalPadding: 8),
      ],
    );
  }
}
