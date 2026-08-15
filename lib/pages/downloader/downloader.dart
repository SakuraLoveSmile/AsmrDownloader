import 'package:asmr_downloader/pages/downloader/config_settings/components/asmr_api_channel.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/asmr_proxy.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/debug_mode_check.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/dl_cover_check.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/dl_path_picker.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/download_threads_selector.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/parallel_downloads_selector.dart';
import 'package:asmr_downloader/pages/downloader/search_box/search_box.dart';
import 'package:asmr_downloader/pages/downloader/search_result/search_result.dart';
import 'package:flutter/material.dart';

/// 下载页：只负责「搜索 + 下载」。
/// 整理 / AI 字幕 / 缓存 / 注册表等文件管理功能已移至「作品库」页。
class Downloader extends StatelessWidget {
  const Downloader({super.key});

  @override
  Widget build(BuildContext context) {
    // 注意：Downloader 是 IndexedStack 的子页，不能再包 Expanded，
    // 由 Column 直接撑满 IndexedStack 的约束。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        // 第一行：搜索 + 下载路径 + API channel
        _ToolbarRow(
          children: [
            SearchBox(),
            DownloadPathPicker(),
            AsmrApiChannel(),
          ],
        ),
        const SizedBox(height: 8),
        // 第二行：下载相关配置
        _ToolbarRow(
          children: [
            DlCoverCheck(),
            DownloadThreadsSelector(),
            ParallelDownloadsSelector(),
            DebugModeCheck(),
            AsmrProxy(),
          ],
        ),
        SizedBox(height: 20),
        SearchResult(),
      ],
    );
  }
}

/// 工具条行：浅灰底圆角容器，内部横向可滚动。
class _ToolbarRow extends StatelessWidget {
  const _ToolbarRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: children),
        ),
      ),
    );
  }
}
