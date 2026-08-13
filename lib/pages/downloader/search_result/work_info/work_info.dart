import 'package:asmr_downloader/pages/components/copyable_textbox.dart';
import 'package:asmr_downloader/pages/downloader/search_result/work_info/components/asmr_cv.dart';
import 'package:asmr_downloader/pages/downloader/search_result/work_info/components/asmr_misc_info.dart';
import 'package:asmr_downloader/pages/downloader/search_result/work_info/components/asmr_tags.dart';
import 'package:asmr_downloader/pages/downloader/search_result/work_info/components/asmr_circle_name.dart';
import 'package:asmr_downloader/pages/downloader/search_result/work_info/components/asmr_cover.dart';
import 'package:asmr_downloader/pages/downloader/search_result/work_info/components/asmr_title.dart';
import 'package:asmr_downloader/pages/window_title_bar/move_window.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/work_info_providers.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkInfo extends ConsumerWidget {
  const WorkInfo({super.key, this.horizontalPadding = 20.0});
  final double horizontalPadding;

  static const _verticalPadding = 10.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appWidth = MediaQuery.of(context).size.width;
    final workInfoLoadingState = ref.watch(workInfoLoadingStateProvider);
    return SizedBox(
      width: appWidth * 0.4,
      child: Padding(
        padding:
            EdgeInsets.only(left: horizontalPadding, right: horizontalPadding),
        child: workInfoLoadingState.when(
          data: (data) {
            if (data == null) {
              // 降级模式：work info 获取失败时显示保底信息
              // （标题来自 tracks workTitle / URL 目录面包屑 / sourceId）
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
          error: (error, stack) => _buildFallbackInfo(context, ref),
        ),
      ),
    );
  }

  /// 降级模式：work info 获取失败时展示的保底信息区
  Widget _buildFallbackInfo(BuildContext context, WidgetRef ref) {
    final sourceId = ref.watch(sourceIdProvider) ?? '';
    final fallbackTitle = ref.watch(titleProvider);
    return MoveWindow(
      moveOnChildWidget: true,
      child: SingleChildScrollView(
        child: Column(
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
          ],
        ),
      ),
    );
  }
}
