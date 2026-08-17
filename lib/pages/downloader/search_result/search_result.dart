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
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: WorkInfo(horizontalPadding: _horizontalPadding),
          ),
          Expanded(
            flex: 3,
            child: TracksView(horizontalPadding: _horizontalPadding),
          ),
        ],
      ),
    );
  }
}
