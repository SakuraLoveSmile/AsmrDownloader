import 'package:asmr_downloader/services/library/library_providers.dart';
import 'package:asmr_downloader/services/library/works_library_service.dart';
import 'package:asmr_downloader/services/transcribe/transcribe_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:asmr_downloader/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 已下载作品列表：
/// 每行显示 RJ 号、标题、CV、音轨/缺字幕统计与状态，支持行内操作
/// （整理 / AI 字幕 / vtt 转 lrc / 打开目录）与多选批量操作。
class LibraryWorkList extends ConsumerStatefulWidget {
  const LibraryWorkList({super.key});

  @override
  ConsumerState<LibraryWorkList> createState() => LibraryWorkListState();
}

class LibraryWorkListState extends ConsumerState<LibraryWorkList> {
  /// 多选：选中的 sourceId 集合
  final Set<String> _selected = {};

  /// 是否已有选中项（供外部工具栏判断）
  bool get hasSelection => _selected.isNotEmpty;

  /// 批量整理当前选中项（外部工具栏可调用）
  Future<void> organizeSelected() => _organizeSelected();

  /// 批量生成字幕（外部工具栏可调用）
  Future<void> transcribeSelected() => _transcribeSelected();

  @override
  Widget build(BuildContext context) {
    final worksAsync = ref.watch(worksLibraryProvider);
    final activeSourceId = ref.watch(activeTranscribeSourceIdProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(worksAsync, activeSourceId),
        const SizedBox(height: 4),
        const Divider(height: 1),
        Expanded(
          child: worksAsync.when(
            loading: () => Center(
                child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2))),
            error: (e, _) => Center(
                child: Text('加载作品库失败: $e',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
            data: (works) => _buildList(works, activeSourceId),
          ),
        ),
      ],
    );
  }

  // ---------- 头部 ----------

  Widget _buildHeader(
      AsyncValue<List<WorksListItem>> worksAsync, String? activeSourceId) {
    final scheme = Theme.of(context).colorScheme;
    final works = worksAsync.value ?? const <WorksListItem>[];
    final selectedCount = _selected.length;
    final batchBusy = activeSourceId != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Text('作品库（${works.length}）',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          if (selectedCount > 0) ...[
            const SizedBox(width: 12),
            Text('已选 $selectedCount',
                style: TextStyle(color: scheme.primary, fontSize: 12)),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: batchBusy ? null : _organizeSelected,
              child: const Text('整理所选'),
            ),
            const SizedBox(width: 4),
            OutlinedButton(
              onPressed: batchBusy ? null : _transcribeSelected,
              child: const Text('字幕所选'),
            ),
            const SizedBox(width: 4),
            OutlinedButton(
              onPressed: () => _toggleSelectAll(works),
              child: Text(_isAllSelected(works) ? '取消全选' : '全选'),
            ),
          ],
          const Spacer(),
          IconButton(
            onPressed: () {
              ref.invalidate(worksLibraryProvider);
              ref.invalidate(unorganizedCountProvider);
            },
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: '刷新作品库',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  // ---------- 列表 ----------

  Widget _buildList(List<WorksListItem> works, String? activeSourceId) {
    if (works.isEmpty) {
      return Center(
        child: Text('暂无已下载作品\n（设置下载路径并下载后自动出现）',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      itemCount: works.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, i) => _WorkRow(
        item: works[i],
        selected: _selected.contains(works[i].sourceId),
        transcribing: activeSourceId == works[i].sourceId,
        onToggleSelect: () => _toggleSelect(works[i].sourceId),
      ),
    );
  }

  // ---------- 选择 ----------

  void _toggleSelect(String sourceId) {
    setState(() {
      if (!_selected.remove(sourceId)) _selected.add(sourceId);
    });
  }

  void _toggleSelectAll(List<WorksListItem> works) {
    setState(() {
      if (_isAllSelected(works)) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(works.map((w) => w.sourceId));
      }
    });
  }

  bool _isAllSelected(List<WorksListItem> works) {
    return works.isNotEmpty && works.every((w) => _selected.contains(w.sourceId));
  }

  // ---------- 批量操作 ----------

  Future<void> _organizeSelected() async {
    final works = ref.read(worksLibraryProvider).value ?? const [];
    final items = works.where((w) => _selected.contains(w.sourceId)).toList();
    if (items.isEmpty) return;

    final ui = ref.read(uiServiceProvider);
    var ok = 0;
    var fail = 0;
    final metadataNotes = <String>{};
    for (final item in items) {
      final outcome = await ui.organizeWorkFor(item, pickPathIfEmpty: true);
      if (outcome?.result != null) {
        ok++;
        final note = outcome?.metadataNote;
        if (note != null && note.isNotEmpty) metadataNotes.add(note);
      } else {
        fail++;
      }
    }
    final noteSuffix =
        metadataNotes.isEmpty ? '' : '；${metadataNotes.join('；')}';
    ui.showSnack('整理所选完成：成功 $ok，失败 $fail$noteSuffix');
    if (mounted) setState(_selected.clear);
  }

  Future<void> _transcribeSelected() async {
    final works = ref.read(worksLibraryProvider).value ?? const [];
    final items = works.where((w) => _selected.contains(w.sourceId)).toList();
    if (items.isEmpty) return;

    final ui = ref.read(uiServiceProvider);
    // 批量聚合：所有选中作品的缺字幕目录一次传给 ChickenRice
    // （一次进程、一次模型加载，进度为跨作品总进度）
    await ui.transcribeWorks(
      [
        for (final item in items)
          (sourceId: item.sourceId, sourceDir: item.sourceDir),
      ],
      pickScriptIfEmpty: true,
    );
    if (mounted) setState(_selected.clear);
  }
}

/// 单行作品。
class _WorkRow extends ConsumerStatefulWidget {
  const _WorkRow({
    required this.item,
    required this.selected,
    required this.transcribing,
    required this.onToggleSelect,
  });

  final WorksListItem item;
  final bool selected;
  final bool transcribing;
  final VoidCallback onToggleSelect;

  @override
  ConsumerState<_WorkRow> createState() => _WorkRowState();
}

class _WorkRowState extends ConsumerState<_WorkRow> {
  /// 鼠标悬停高亮
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final selected = widget.selected;
    final transcribing = widget.transcribing;
    final onToggleSelect = widget.onToggleSelect;
    final scheme = Theme.of(context).colorScheme;
    final ui = ref.read(uiServiceProvider);

    // 状态标签：色底 + 深字的圆角 chip
    final (String statusLabel, Color statusFg, Color statusBg) = transcribing
        ? ('字幕中', scheme.primary,
            scheme.primaryContainer.withValues(alpha: 0.5))
        : item.organized
            ? ('已整理', AppColors.success, AppColors.successBg)
            : item.missingSubtitleCount > 0
                ? ('未整理', AppColors.warning, AppColors.warningBg)
                : ('未整理', AppColors.info, AppColors.infoBg);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.06)
              : _hovered
                  ? scheme.surfaceContainerHighest
                  : scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.45)
                  : scheme.outlineVariant,
              width: 1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
        children: [
          Checkbox(
            value: selected,
            onChanged: (_) => onToggleSelect(),
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(item.sourceId,
                        style: TextStyle(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(item.title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (item.cvNames.isNotEmpty) ...[
                      Text(item.cvNames,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: scheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                              fontSize: 11)),
                      const SizedBox(width: 8),
                    ],
                    Text('音轨 ${item.trackCount}',
                        style: TextStyle(
                            color:
                                scheme.onSurfaceVariant.withValues(alpha: 0.7),
                            fontSize: 11)),
                    if (item.missingSubtitleCount > 0) ...[
                      const SizedBox(width: 8),
                      Text('缺字幕 ${item.missingSubtitleCount}',
                          style: const TextStyle(
                              color: AppColors.warning, fontSize: 11)),
                    ],
                    if (item.convertibleVttCount > 0) ...[
                      const SizedBox(width: 8),
                      Text('vtt ${item.convertibleVttCount}',
                          style: const TextStyle(
                              color: AppColors.info, fontSize: 11)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // 状态标签
          if (transcribing)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: scheme.primary),
              ),
            ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: statusBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(color: statusFg, fontSize: 11),
            ),
          ),
          const SizedBox(width: 8),
          // 行内操作
          _RowIconBtn(
            icon: Icons.folder_open,
            tooltip: '打开目录',
            onTap: () => ui.openFolderForDir(item.sourceDir),
          ),
          _RowIconBtn(
            icon: Icons.library_music_outlined,
            tooltip: '整理到 Navidrome',
            onTap: () async {
              final outcome =
                  await ui.organizeWorkFor(item, pickPathIfEmpty: true);
              final result = outcome?.result;
              if (result != null) {
                final note = outcome?.metadataNote;
                final suffix = note == null ? '' : '；$note';
                ui.showSnack(
                    '整理完成：复制 ${result.copied} 个文件，跳过 ${result.skipped} 个$suffix');
              } else {
                ui.showSnack('整理未执行（未设置整理路径或目录缺失）');
              }
            },
          ),
          _RowIconBtn(
            icon: Icons.subtitles_outlined,
            tooltip: 'AI 生成字幕（ChickenRice）',
            enabled: !transcribing,
            onTap: () => ui.transcribeWork(item.sourceId, item.sourceDir,
                pickScriptIfEmpty: true),
          ),
          _RowIconBtn(
            icon: Icons.lyrics_outlined,
            tooltip: 'vtt 转 lrc 歌词',
            enabled: item.convertibleVttCount > 0 && !transcribing,
            onTap: () => ui.convertVttToLrcForWork(item.sourceDir),
          ),
          ],
        ),
      ),
    );
  }
}

class _RowIconBtn extends StatelessWidget {
  const _RowIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: IconButton(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, size: 17),
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        color: enabled
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
      ),
    );
  }
}
