import 'package:asmr_downloader/pages/downloader/search_result/tracks_view/tracks_view.dart';
import 'package:asmr_downloader/pages/downloader/search_result/work_info/work_info.dart';
import 'package:flutter/material.dart';

class SearchResult extends StatelessWidget {
  const SearchResult({super.key});
  static const _horizontalPadding = 12.0;

  @override
  Widget build(BuildContext context) {
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
