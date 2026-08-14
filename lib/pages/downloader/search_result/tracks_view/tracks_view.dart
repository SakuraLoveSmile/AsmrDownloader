import 'package:asmr_downloader/pages/downloader/search_result/empty_guidance.dart';
import 'package:asmr_downloader/pages/downloader/search_result/tracks_view/components/download_progress/download_progress.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/tracks_providers.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/work_info_providers.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/pages/downloader/search_result/tracks_view/components/tracks.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TracksView extends ConsumerWidget {
  const TracksView({super.key, this.horizontalPadding = 20.0});
  final double horizontalPadding;

  static const _tracksLPadding = 20.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appWidth = MediaQuery.of(context).size.width;
    final tracksLoadingState = ref.watch(tracksLoadingStateProvider);
    return SizedBox(
      width: appWidth * 0.6,
      child: Padding(
        padding: EdgeInsets.only(right: horizontalPadding, bottom: 10.0),
        child: tracksLoadingState.when(
          data: (_) {
            // 尚未搜索：显示引导而非空白
            if (ref.read(searchTextProvider) == null) {
              return const EmptyGuidance();
            }
            final rootFolder = ref.read(rootFolderProvider);
            if (ref.read(workInfoLoadingStateProvider).value == null ||
                rootFolder == null) {
              return const Center(
                child: Text('未找到音轨数据',
                    style: TextStyle(color: Colors.white54)),
              );
            }

            return Column(
              children: [
                DownloadProgress(tracksLPadding: _tracksLPadding),
                Expanded(
                  child: Tracks(
                    rootFolder: rootFolder,
                    tracksLPadding: _tracksLPadding,
                  ),
                ),
              ],
            );
          },
          loading: () => Center(child: const CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '加载失败：$error',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => ref
                    ..invalidate(searchResultProvider)
                    ..invalidate(workInfoProvider)
                    ..invalidate(rawTracksProvider)
                    ..invalidate(coverBytesProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
