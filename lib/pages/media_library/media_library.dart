import 'dart:math' as math;

import 'package:asmr_downloader/pages/media_library/components/batch_cache_dialog.dart';
import 'package:asmr_downloader/pages/media_library/components/cache_dialog.dart';
import 'package:asmr_downloader/pages/media_library/components/complete_missing_dialog.dart';
import 'package:asmr_downloader/pages/media_library/components/cv_stats_dialog.dart';
import 'package:asmr_downloader/pages/media_library/components/cached_work_card.dart';
import 'package:asmr_downloader/pages/media_library/components/media_library_settings_dialog.dart';
import 'package:asmr_downloader/pages/media_library/components/work_inspector_drawer.dart';
import 'package:asmr_downloader/services/cache/cache_library_providers.dart';
import 'package:asmr_downloader/services/library/work_library_status.dart';
import 'package:asmr_downloader/ui/page_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 媒体库：扫描配置目录中的 RJ/VJ/BJ 目录，再与本地 API 元数据数据库关联。
/// 扫描只建立作品存在性索引，不读取音轨、字幕或封面明细。
class MediaLibraryPage extends ConsumerStatefulWidget {
  const MediaLibraryPage({super.key});

  @override
  ConsumerState<MediaLibraryPage> createState() => _MediaLibraryPageState();
}

class _MediaLibraryPageState extends ConsumerState<MediaLibraryPage> {
  late final TextEditingController _searchController;
  CachedLibraryEntry? _selectedEntry;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(cacheSearchQueryProvider),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilter(String query) {
    _searchController.text = query;
    ref.read(cacheSearchQueryProvider.notifier).state = query;
    setState(() {});
  }

  /// 重扫/删除后刷新媒体库列表与搜索页的入库状态徽章
  /// （扫描会更新媒体库位置记录，入库判定随之变化）。
  void _refreshLibrary() {
    ref.invalidate(cachedLibraryProvider);
    ref.invalidate(workLibraryStatusProvider);
  }

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(cachedLibraryProvider);
    final filteredAsync = ref.watch(filteredCachedLibraryProvider);
    final total = libraryAsync.value?.entries.length;
    final matched = filteredAsync.value?.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          icon: Icons.photo_library_rounded,
          title: '媒体库',
          subtitle: '浏览已缓存与已扫描的作品元数据',
        ),
        _buildToolbar(total, matched),
        const Divider(height: 1),
        Expanded(
          child: filteredAsync.when(
            loading: () => const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (error, _) => _buildError(error),
            data: (entries) => _buildContent(entries, total ?? entries.length),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(int? total, int? matched) {
    final sort = ref.watch(cacheSortProvider);
    final groupBy = ref.watch(mediaLibraryGroupByProvider);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Container(
        key: const ValueKey('onboarding-media-toolbar'),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant, width: 0.8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 270,
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 12.5),
                onChanged: (value) =>
                    ref.read(cacheSearchQueryProvider.notifier).state = value,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 16,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                  hintText: '搜索 ID / 标题 / 社团 / CV',
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            ref.read(cacheSearchQueryProvider.notifier).state =
                                '';
                            setState(() {});
                          },
                          icon: Icon(
                            Icons.cancel_rounded,
                            size: 15,
                            color:
                                scheme.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                          tooltip: '清除搜索',
                          splashRadius: 14,
                          visualDensity: VisualDensity.compact,
                        ),
                ),
              ),
            ),
            _buildSortSelector(sort),
            _buildGroupSelector(groupBy),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: scheme.outlineVariant, width: 0.6),
              ),
              child: Text(
                '共 ${total ?? '…'} 条 · 命中 ${matched ?? '…'} 条',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _refreshLibrary,
              icon: const Icon(Icons.manage_search_rounded, size: 15),
              label: const Text('扫描目录'),
            ),
            IconButton(
              onPressed: _refreshLibrary,
              icon: const Icon(Icons.refresh_rounded, size: 17),
              tooltip: '重新扫描目录',
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                shape: const CircleBorder(),
                backgroundColor:
                    scheme.surfaceContainerHigh.withValues(alpha: 0.4),
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('onboarding-cache-management'),
              onPressed: _openCacheManagement,
              icon: const Icon(Icons.tune_rounded, size: 15),
              label: const Text('数据库管理'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('cv-stats'),
              onPressed: _openCvStats,
              icon: const Icon(Icons.person_search_rounded, size: 15),
              label: const Text('CV 统计'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('onboarding-media-library-settings'),
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined, size: 15),
              label: const Text('媒体库设置'),
            ),
            BatchCacheButton(
              onClosed: _refreshLibrary,
            ),
            OutlinedButton.icon(
              key: const ValueKey('onboarding-complete-missing'),
              onPressed: _openCompleteMissing,
              icon: const Icon(Icons.auto_fix_high_rounded, size: 15),
              label: const Text('一键补全'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupSelector(MediaLibraryGroupBy groupBy) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
        border: Border.all(color: scheme.outlineVariant, width: 0.8),
        borderRadius: BorderRadius.circular(100),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<MediaLibraryGroupBy>(
          value: groupBy,
          isDense: true,
          style: TextStyle(color: scheme.onSurface, fontSize: 12),
          dropdownColor: scheme.surfaceContainerHigh,
          icon: const Icon(Icons.account_tree_outlined, size: 15),
          onChanged: (value) {
            if (value != null) {
              ref.read(mediaLibraryGroupByProvider.notifier).state = value;
            }
          },
          items: const [
            DropdownMenuItem(
              value: MediaLibraryGroupBy.none,
              child: Text('平铺浏览'),
            ),
            DropdownMenuItem(
              value: MediaLibraryGroupBy.circle,
              child: Text('按社团分类'),
            ),
            DropdownMenuItem(
              value: MediaLibraryGroupBy.cv,
              child: Text('按 CV 分类'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortSelector(CacheSort sort) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
        border: Border.all(color: scheme.outlineVariant, width: 0.8),
        borderRadius: BorderRadius.circular(100),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<CacheSort>(
          value: sort,
          isDense: true,
          style: TextStyle(color: scheme.onSurface, fontSize: 12),
          dropdownColor: scheme.surfaceContainerHigh,
          icon: const Icon(Icons.unfold_more_rounded, size: 15),
          onChanged: (value) {
            if (value != null) {
              ref.read(cacheSortProvider.notifier).state = value;
            }
          },
          items: const [
            DropdownMenuItem(
              value: CacheSort.cachedAt,
              child: Text('缓存时间倒序'),
            ),
            DropdownMenuItem(
              value: CacheSort.releaseDate,
              child: Text('发售日期'),
            ),
            DropdownMenuItem(
              value: CacheSort.title,
              child: Text('标题'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(List<CachedLibraryEntry> entries, int total) {
    if (total == 0) {
      return _buildEmpty(
        icon: Icons.photo_library_outlined,
        message: '暂无扫描到的作品\n请在媒体库设置中添加下载目录或已挂载的 NAS 目录。',
      );
    }
    if (entries.isEmpty) {
      return _buildEmpty(
        icon: Icons.search_off,
        message: '没有匹配的缓存作品\n可以尝试其他 sourceId、标题、社团或 CV 关键词。',
      );
    }

    final selected = _selectedEntry;
    // 如果之前选中的 entry 已不在当前过滤列表中，自动置空
    final currentSelectedEntry =
        selected != null && entries.any((e) => e.sourceId == selected.sourceId)
            ? entries.firstWhere((e) => e.sourceId == selected.sourceId)
            : null;

    final groupBy = ref.watch(mediaLibraryGroupByProvider);
    final grid = groupBy == MediaLibraryGroupBy.none
        ? _buildFlatGrid(entries, currentSelectedEntry)
        : _buildGroupedGrid(entries, groupBy, currentSelectedEntry);

    return Row(
      children: [
        Expanded(child: grid),
        if (currentSelectedEntry != null)
          WorkInspectorDrawer(
            entry: currentSelectedEntry,
            onClose: () => setState(() => _selectedEntry = null),
            onRemoved: () => setState(() => _selectedEntry = null),
            onSelectTag: _applyFilter,
            onSelectCv: _applyFilter,
          ),
      ],
    );
  }

  Widget _buildFlatGrid(
    List<CachedLibraryEntry> entries,
    CachedLibraryEntry? selectedEntry,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final columns = _columnCount(constraints.maxWidth);
        final gridWidth = math
            .min(
              constraints.maxWidth,
              columns * _targetCardWidth + (columns - 1) * gap + 24,
            )
            .toDouble();
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: gridWidth,
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 20),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent: 312,
                crossAxisSpacing: gap,
                mainAxisSpacing: 14,
              ),
              itemCount: entries.length,
              itemBuilder: (context, index) => _buildWorkCard(
                entries[index],
                selectedEntry,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGroupedGrid(
    List<CachedLibraryEntry> entries,
    MediaLibraryGroupBy groupBy,
    CachedLibraryEntry? selectedEntry,
  ) {
    final groups = _groupEntries(entries, groupBy);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final columns = _columnCount(constraints.maxWidth);
        return ListView(
          key: ValueKey('media-library-grouped-list-${groupBy.name}'),
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 20),
          children: [
            for (final group in groups.entries) ...[
              _buildGroupHeader(context, group.key, group.value.length),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: 312,
                  crossAxisSpacing: gap,
                  mainAxisSpacing: 14,
                ),
                itemCount: group.value.length,
                itemBuilder: (context, index) => _buildWorkCard(
                  group.value[index],
                  selectedEntry,
                ),
              ),
              const SizedBox(height: 18),
            ],
          ],
        );
      },
    );
  }

  Widget _buildGroupHeader(BuildContext context, String title, int count) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: scheme.outlineVariant, width: 0.7),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkCard(
    CachedLibraryEntry entry,
    CachedLibraryEntry? selectedEntry,
  ) {
    final isSelected = selectedEntry?.sourceId == entry.sourceId;
    return CachedWorkCard(
      entry: entry,
      isSelected: isSelected,
      onTap: () {
        setState(() {
          _selectedEntry = isSelected ? null : entry;
        });
      },
      onRemoved: () {
        if (isSelected) {
          setState(() => _selectedEntry = null);
        } else {
          setState(() {});
        }
      },
    );
  }

  static const _targetCardWidth = 176.0;

  static int _columnCount(double width) {
    const gap = 12.0;
    return math
        .max(1, ((width + gap) / (_targetCardWidth + gap)).floor())
        .toInt();
  }

  Map<String, List<CachedLibraryEntry>> _groupEntries(
    List<CachedLibraryEntry> entries,
    MediaLibraryGroupBy groupBy,
  ) {
    final grouped = <String, List<CachedLibraryEntry>>{};
    for (final entry in entries) {
      final names = switch (groupBy) {
        MediaLibraryGroupBy.circle => entry.circleName.trim().isEmpty
            ? const ['未关联社团']
            : [entry.circleName.trim()],
        MediaLibraryGroupBy.cv => entry.cvNames
                .map((name) => name.trim())
                .where((name) => name.isNotEmpty)
                .toSet()
                .toList()
                .isEmpty
            ? const ['未关联 CV']
            : entry.cvNames
                .map((name) => name.trim())
                .where((name) => name.isNotEmpty)
                .toSet()
                .toList(),
        MediaLibraryGroupBy.none => const ['全部'],
      };
      for (final name in names) {
        grouped.putIfAbsent(name, () => []).add(entry);
      }
    }

    final sortedKeys = grouped.keys.toList()
      ..sort((left, right) {
        final leftMissing = left.startsWith('未关联');
        final rightMissing = right.startsWith('未关联');
        if (leftMissing != rightMissing) return leftMissing ? 1 : -1;
        return left.toLowerCase().compareTo(right.toLowerCase());
      });
    return {
      for (final key in sortedKeys) key: grouped[key]!,
    };
  }

  Widget _buildEmpty({required IconData icon, required String message}) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildError(Object error) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 40, color: scheme.error),
          const SizedBox(height: 10),
          Text('加载媒体库失败：$error', style: TextStyle(color: scheme.error)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _refreshLibrary,
            icon: const Icon(Icons.refresh, size: 17),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Future<void> _openCacheManagement() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const CacheDialog(),
    );
    if (mounted) _refreshLibrary();
  }

  Future<void> _openCompleteMissing() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const CompleteMissingDialog(),
    );
    if (mounted) _refreshLibrary();
  }

  Future<void> _openSettings() {
    return showDialog<void>(
      context: context,
      builder: (_) => const MediaLibrarySettingsDialog(),
    );
  }

  Future<void> _openCvStats() {
    return showDialog<void>(
      context: context,
      builder: (_) => CvStatsDialog(onViewWorks: _applyFilter),
    );
  }
}
