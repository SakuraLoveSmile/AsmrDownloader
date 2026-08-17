import 'package:asmr_downloader/pages/downloader/config_settings/components/asmr_api_channel.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/asmr_proxy.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/auto_update_check.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/debug_mode_check.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/dl_cover_check.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/dl_path_picker.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/download_threads_selector.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/github_token_button.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/log_viewer_button.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/parallel_downloads_selector.dart';
import 'package:asmr_downloader/pages/downloader/search_box/search_box.dart';
import 'package:asmr_downloader/pages/downloader/search_result/search_result.dart';
import 'package:asmr_downloader/ui/toolbar_row.dart';
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
        AppToolbarRow(
          children: [
            SearchBox(),
            DownloadPathPicker(),
            AsmrApiChannel(),
          ],
        ),
        const SizedBox(height: 8),
        // 第二行：下载相关配置
        AppToolbarRow(
          children: [
            DlCoverCheck(),
            DownloadThreadsSelector(),
            ParallelDownloadsSelector(),
            DebugModeCheck(),
            LogViewerButton(),
            AutoUpdateCheck(),
            GithubTokenButton(),
            AsmrProxy(),
          ],
        ),
        const SizedBox(height: 8),
        SearchResult(),
      ],
    );
  }
}
