import 'package:asmr_downloader/pages/downloader/search_result/tracks_view/tracks_view.dart';
import 'package:asmr_downloader/pages/downloader/search_result/empty_guidance.dart';
import 'package:asmr_downloader/pages/downloader/search_result/work_info/work_info.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SearchResult extends ConsumerWidget {
  const SearchResult({super.key});
  static const _horizontalPadding = 12.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 初始状态由父级统一渲染，避免左右两栏各显示一份相同的引导。
    if (ref.watch(searchTextProvider) == null) {
      return const Expanded(child: EmptyGuidance());
    }

    return Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SizedBox(
              width: double.infinity,
              child: WorkInfo(horizontalPadding: _horizontalPadding),
            ),
          ),
          Expanded(
            child: TracksView(horizontalPadding: _horizontalPadding),
          ),
        ],
      ),
    );
  }
}
