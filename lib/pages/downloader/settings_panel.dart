import 'package:asmr_downloader/pages/downloader/config_settings/components/asmr_proxy.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/auto_update_check.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/debug_mode_check.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/dl_cover_check.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/download_threads_selector.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/github_token_button.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/log_viewer_button.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/onboarding_button.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/parallel_downloads_selector.dart';
import 'package:flutter/material.dart';

/// Compact settings panel for the downloader page.
class DownloaderSettingsPanel extends StatelessWidget {
  const DownloaderSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '下载设置',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: '关闭',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _SettingsSection(
                  title: '下载',
                  children: const [
                    DlCoverCheck(),
                    DownloadThreadsSelector(),
                    ParallelDownloadsSelector(),
                  ],
                ),
                const SizedBox(height: 12),
                _SettingsSection(
                  title: '网络',
                  children: const [
                    AsmrProxy(),
                    GithubTokenButton(),
                  ],
                ),
                const SizedBox(height: 12),
                _SettingsSection(
                  title: '其它',
                  children: const [
                    LogViewerButton(),
                    DebugModeCheck(),
                    AutoUpdateCheck(),
                    OnboardingButton(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: children,
        ),
      ],
    );
  }
}
