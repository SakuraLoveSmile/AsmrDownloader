import 'package:asmr_downloader/services/library/library_providers.dart';
import 'package:asmr_downloader/services/library/works_library_service.dart';
import 'package:asmr_downloader/services/transcribe/transcribe_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
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
        const Divider(height: 1, color: Colors.white12),
        Expanded(
          child: worksAsync.when(
            loading: () => Center(
                child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2))),
            error: (e, _) => Center(
                child: Text('加载作品库失败: $e',
                    style: const TextStyle(color: Colors.redAccent))),
            data: (works) => _buildList(works, activeSourceId),
          ),
        ),
      ],
    );
  }

  // ---------- 头部 ----------

  Widget _buildHeader(
      AsyncValue<List<WorksListItem>> worksAsync, String? activeSourceId) {
    final works = worksAsync.value ?? const <WorksListItem>[];
    final selectedCount = _selected.length;
    final batchBusy = activeSourceId != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Text('作品库（${works.length}）',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          if (selectedCount > 0) ...[
            const SizedBox(width: 12),
            Text('已选 $selectedCount',
                style: const TextStyle(color: Colors.amber, fontSize: 12)),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: batchBusy ? null : _organizeSelected,
              style: _miniBtnStyle(),
              child: const Text('整理所选'),
            ),
            const SizedBox(width: 4),
            OutlinedButton(
              onPressed: batchBusy ? null : _transcribeSelected,
              style: _miniBtnStyle(),
              child: const Text('字幕所选'),
            ),
            const SizedBox(width: 4),
            OutlinedButton(
              onPressed: () => _toggleSelectAll(works),
              style: _miniBtnStyle(),
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
            color: Colors.white54,
          ),
        ],
      ),
    );
  }

  ButtonStyle _miniBtnStyle() => OutlinedButton.styleFrom(
        side: BorderSide(color: Colors.white24),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        foregroundColor: Colors.white70,
        disabledForegroundColor: Colors.white24,
        minimumSize: const Size(0, 28),
        textStyle: const TextStyle(fontSize: 12),
      );

  // ---------- 列表 ----------

  Widget _buildList(List<WorksListItem> works, String? activeSourceId) {
    if (works.isEmpty) {
      return const Center(
        child: Text('暂无已下载作品\n（设置下载路径并下载后自动出现）',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 13)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
    for (final item in items) {
      final result = await ui.organizeWorkFor(item, pickPathIfEmpty: true);
      if (result != null) {
        ok++;
      } else {
        fail++;
      }
    }
    ui.showSnack('整理所选完成：成功 $ok，失败 $fail');
    if (mounted) setState(_selected.clear);
  }

  Future<void> _transcribeSelected() async {
    final works = ref.read(worksLibraryProvider).value ?? const [];
    final items = works.where((w) => _selected.contains(w.sourceId)).toList();
    if (items.isEmpty) return;

    final ui = ref.read(uiServiceProvider);
    for (final item in items) {
      // 串行：前一个完成后状态复位，下一个才能开始
      await ui.transcribeWork(item.sourceId, item.sourceDir,
          pickScriptIfEmpty: true);
    }
    if (mounted) setState(_selected.clear);
  }
}

/// 单行作品。
class _WorkRow extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.read(uiServiceProvider);
    final statusColor = item.organized
        ? Colors.greenAccent
        : (item.missingSubtitleCount > 0 ? Colors.amber : Colors.blueAccent);

    return Container(
      decoration: BoxDecoration(
        color: selected
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: selected ? Colors.white24 : Colors.white10, width: 1),
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
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(item.title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (item.cvNames.isNotEmpty) ...[
                      Text(item.cvNames,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11)),
                      const SizedBox(width: 8),
                    ],
                    Text('音轨 ${item.trackCount}',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11)),
                    if (item.missingSubtitleCount > 0) ...[
                      const SizedBox(width: 8),
                      Text('缺字幕 ${item.missingSubtitleCount}',
                          style: const TextStyle(
                              color: Colors.amber, fontSize: 11)),
                    ],
                    if (item.convertibleVttCount > 0) ...[
                      const SizedBox(width: 8),
                      Text('vtt ${item.convertibleVttCount}',
                          style: const TextStyle(
                              color: Colors.lightBlueAccent, fontSize: 11)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // 状态标签
          if (transcribing)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          Text(
            transcribing
                ? '字幕中'
                : (item.organized ? '已整理' : '未整理'),
            style: TextStyle(color: statusColor, fontSize: 11),
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
              final result =
                  await ui.organizeWorkFor(item, pickPathIfEmpty: true);
              if (result != null) {
                ui.showSnack(
                    '整理完成：复制 ${result.copied} 个文件，跳过 ${result.skipped} 个');
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
        color: enabled ? Colors.white60 : Colors.white24,
      ),
    );
  }
}
