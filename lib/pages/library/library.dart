import 'package:asmr_downloader/pages/library/tools/batch_verify_dialog.dart';
import 'package:asmr_downloader/pages/library/tools/complete_works_dialog.dart';
import 'package:asmr_downloader/pages/library/tools/library_config_dialog.dart';
import 'package:asmr_downloader/pages/library/tools/organize_all_button.dart';
import 'package:asmr_downloader/pages/library/tools/transcribe_status_indicator.dart';
import 'package:asmr_downloader/pages/library/work_list.dart';
import 'package:asmr_downloader/services/library/library_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:asmr_downloader/ui/page_header.dart';
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
    final works = ref.watch(worksLibraryProvider).value ?? const [];
    final repairableCount =
        works.where((w) => w.verifyNote != null && w.verifyRepairable).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(
          icon: Icons.folder_copy_rounded,
          title: '作品库',
          subtitle: '管理本机下载与 NAS 整理状态',
        ),
        // 单行紧凑工具栏：核心操作 + 偏好配置
        AppToolbarRow(
          key: const ValueKey('onboarding-library-toolbar'),
          children: [
            const OrganizeAllButton(),
            const WorksIndexButton(),
            const VerifyButton(),
            const CompleteWorksButton(),
            if (repairableCount > 0)
              OutlinedButton(
                onPressed: () =>
                    _workListKey.currentState?.repairRepairable(),
                child: Text('修复缺陷（$repairableCount）'),
              ),
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

/// 整理产物校验按钮：打开批量校验对话框（进度/取消/修复缺失）。
class VerifyButton extends ConsumerWidget {
  const VerifyButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton(
      onPressed: () => showDialog(
        context: context,
        builder: (_) => const BatchVerifyDialog(),
      ),
      child: const Text('校验'),
    );
  }
}

/// 作品库「补全数据」按钮：打开补全对话框（补全下载作品的元数据、
/// tracks/封面缓存并回写注册表，加入后台任务队列执行）。
class CompleteWorksButton extends ConsumerWidget {
  const CompleteWorksButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton(
      onPressed: () => showDialog(
        context: context,
        builder: (_) => const CompleteWorksDialog(),
      ),
      child: const Text('补全数据'),
    );
  }
}
