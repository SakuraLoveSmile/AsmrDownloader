import 'package:asmr_downloader/pages/downloader/config_settings/components/asmr_api_channel.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/dl_path_picker.dart';
import 'package:asmr_downloader/pages/downloader/search_box/search_box.dart';
import 'package:asmr_downloader/pages/downloader/search_result/search_result.dart';
import 'package:asmr_downloader/pages/downloader/settings_panel.dart';
import 'package:asmr_downloader/ui/page_header.dart';
import 'package:asmr_downloader/ui/toolbar_row.dart';
import 'package:flutter/material.dart';

/// 下载页：只负责「搜索 + 下载」。
/// 整理 / AI 字幕 / 缓存 / 注册表等文件管理功能已移至「作品库」页。
class Downloader extends StatelessWidget {
  const Downloader({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(
          icon: Icons.arrow_circle_down_rounded,
          title: '下载中心',
          subtitle: '输入 sourceId 或拖入链接下载',
        ),
        // 搜索 + 下载路径 + API channel + 设置
        AppToolbarRow(
          children: [
            const SearchBox(),
            const DownloadPathPicker(),
            const AsmrApiChannel(),
            IconButton(
              key: const ValueKey('onboarding-settings'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const DownloaderSettingsPanel(),
              ),
              icon: const Icon(Icons.tune_rounded, size: 18),
              tooltip: '下载设置',
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                shape: const CircleBorder(),
                backgroundColor:
                    scheme.surfaceContainerHigh.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const SearchResult(),
      ],
    );
  }
}
