import 'package:asmr_downloader/pages/library/tools/auto_organize_check.dart';
import 'package:asmr_downloader/pages/library/tools/batch_cache_dialog.dart';
import 'package:asmr_downloader/pages/library/tools/cache_dialog.dart';
import 'package:asmr_downloader/pages/library/tools/chicken_rice_config_controls.dart';
import 'package:asmr_downloader/pages/library/tools/navidrome_path_picker.dart';
import 'package:asmr_downloader/pages/library/tools/organize_all_button.dart';
import 'package:asmr_downloader/pages/library/tools/transcribe_status_indicator.dart';
import 'package:asmr_downloader/pages/library/work_list.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 作品库 / 文件管理页：
/// 整理（Navidrome）、AI 字幕（ChickenRice）、歌词转换、缓存、注册表，
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
    // 注意：LibraryPage 是 IndexedStack 的子页，不能再包 Expanded，
    // 由 Column 直接撑满 IndexedStack 的约束。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        // 工具栏第一行：整理路径 + 自动整理 + AI 字幕配置
        _ToolbarRow(
          children: [
            NavidromePathPicker(),
            AutoOrganizeCheck(),
            ChickenRiceConfigControls(),
          ],
        ),
        const SizedBox(height: 8),
        // 工具栏第二行：批量整理 / 注册表 / 缓存 / 字幕
        _ToolbarRow(
          children: [
            OrganizeAllButton(),
            WorksIndexButton(),
            CacheButton(),
            BatchCacheButton(),
            TranscribeStatusIndicator(onStart: _onToolbarTranscribe),
          ],
        ),
        const SizedBox(height: 8),
        // 作品库内容：已下载作品列表
        Expanded(child: LibraryWorkList(key: _workListKey)),
      ],
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
