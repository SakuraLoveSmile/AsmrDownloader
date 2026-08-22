import 'package:asmr_downloader/pages/library/tools/library_config_dialog.dart';
import 'package:asmr_downloader/pages/library/tools/organize_all_button.dart';
import 'package:asmr_downloader/pages/library/tools/transcribe_status_indicator.dart';
import 'package:asmr_downloader/pages/library/work_list.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:asmr_downloader/ui/toolbar_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 作品库 / 文件管理页：
/// 整理（Navidrome）、AI 字幕（ChickenRice）、歌词转换、注册表，
/// 以及已下载作品列表（多选 + 行内操作）。
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _workListKey = GlobalKey<LibraryWorkListState>();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPageHeader(scheme),
        // 单行紧凑工具栏：核心操作 + 偏好配置
        AppToolbarRow(
          key: const ValueKey('onboarding-library-toolbar'),
          children: [
            const OrganizeAllButton(),
            const WorksIndexButton(),
            TranscribeStatusIndicator(onStart: _onToolbarTranscribe),
            IconButton(
              key: const ValueKey('onboarding-library-config'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const LibraryConfigDialog(),
              ),
              icon: const Icon(Icons.tune_rounded, size: 18),
              tooltip: '整理与 AI 字幕设置',
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
        // 作品库内容：已下载作品列表
        Expanded(child: LibraryWorkList(key: _workListKey)),
      ],
    );
  }

  Widget _buildPageHeader(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(
        children: [
          Icon(Icons.folder_copy_rounded, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          Text(
            '作品库',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '管理本机下载与 NAS 整理状态',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 工具栏「字幕」：对当前勾选的作品生成字幕；未勾选时提示。
  void _onToolbarTranscribe() {
    final listState = _workListKey.currentState;
    if (listState == null || !listState.hasSelection) {
      ref.read(uiServiceProvider).showSnack('请先勾选要生成字幕的作品（列表左侧复选框），或使用行内的字幕按钮');
      return;
    }
    listState.transcribeSelected();
  }
}
