import 'package:asmr_downloader/pages/downloader/config_settings/components/asmr_api_channel.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/dl_path_picker.dart';
import 'package:asmr_downloader/pages/downloader/search_box/search_box.dart';
import 'package:asmr_downloader/pages/downloader/search_result/search_result.dart';
import 'package:asmr_downloader/pages/downloader/settings_panel.dart';
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
        // 搜索 + 下载路径 + API channel + 设置
        AppToolbarRow(
          children: [
            SearchBox(),
            DownloadPathPicker(),
            AsmrApiChannel(),
            IconButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const DownloaderSettingsPanel(),
              ),
              icon: const Icon(Icons.settings_outlined),
              tooltip: '下载设置',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 8),
        SearchResult(),
      ],
    );
  }
}
