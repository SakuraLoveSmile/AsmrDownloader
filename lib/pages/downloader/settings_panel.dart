import 'package:asmr_downloader/pages/downloader/config_settings/components/asmr_proxy.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/auto_update_check.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/debug_mode_check.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/dl_cover_check.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/download_threads_selector.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/github_token_button.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/log_viewer_button.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/notify_on_complete_check.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/onboarding_button.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/parallel_downloads_selector.dart';
import 'package:asmr_downloader/pages/downloader/config_settings/components/theme_mode_selector.dart';
import 'package:flutter/material.dart';

/// Compact settings panel for the downloader page.
class DownloaderSettingsPanel extends StatelessWidget {
  const DownloaderSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant, width: 0.8),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 490),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '下载设置',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: '关闭',
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      shape: const CircleBorder(),
                      backgroundColor:
                          scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      _SettingsSection(
                        title: '外观与通知',
                        icon: Icons.palette_outlined,
                        children: [
                          ThemeModeSelector(),
                          NotifyOnCompleteCheck(),
                        ],
                      ),
                      SizedBox(height: 12),
                      _SettingsSection(
                        title: '下载与线程',
                        icon: Icons.download_rounded,
                        children: [
                          DlCoverCheck(),
                          DownloadThreadsSelector(),
                          ParallelDownloadsSelector(),
                        ],
                      ),
                      SizedBox(height: 12),
                      _SettingsSection(
                        title: '网络与授权',
                        icon: Icons.language_rounded,
                        children: [
                          AsmrProxy(),
                          GithubTokenButton(),
                        ],
                      ),
                      SizedBox(height: 12),
                      _SettingsSection(
                        title: '常规与调试',
                        icon: Icons.tune_rounded,
                        children: [
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
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: children,
          ),
        ],
      ),
    );
  }
}
