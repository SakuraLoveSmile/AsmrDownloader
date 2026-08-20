import 'dart:math' as math;

import 'package:asmr_downloader/pages/media_library/components/batch_cache_dialog.dart';
import 'package:asmr_downloader/pages/media_library/components/cache_dialog.dart';
import 'package:asmr_downloader/pages/media_library/components/complete_missing_dialog.dart';
import 'package:asmr_downloader/pages/media_library/components/cached_work_card.dart';
import 'package:asmr_downloader/pages/media_library/components/work_inspector_drawer.dart';
import 'package:asmr_downloader/services/cache/cache_library_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 本地缓存媒体库：以封面网格展示 workInfo 缓存条目。
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

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(cachedLibraryProvider);
    final filteredAsync = ref.watch(filteredCachedLibraryProvider);
    final total = libraryAsync.value?.entries.length;
    final matched = filteredAsync.value?.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                            ref.read(cacheSearchQueryProvider.notifier).state = '';
                            setState(() {});
                          },
                          icon: Icon(
                            Icons.cancel_rounded,
                            size: 15,
                            color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                          tooltip: '清除搜索',
                          splashRadius: 14,
                          visualDensity: VisualDensity.compact,
                        ),
                ),
              ),
            ),
            _buildSortSelector(sort),
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
            IconButton(
              onPressed: () => ref.invalidate(cachedLibraryProvider),
              icon: const Icon(Icons.refresh_rounded, size: 17),
              tooltip: '刷新媒体库',
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                shape: const CircleBorder(),
                backgroundColor: scheme.surfaceContainerHigh.withValues(alpha: 0.4),
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('onboarding-cache-management'),
              onPressed: _openCacheManagement,
              icon: const Icon(Icons.tune_rounded, size: 15),
              label: const Text('缓存管理'),
            ),
            BatchCacheButton(
              onClosed: () => ref.invalidate(cachedLibraryProvider),
            ),
            OutlinedButton.icon(
              key: const ValueKey('onboarding-complete-missing'),
              onPressed: _openCompleteMissing,
              icon: const Icon(Icons.auto_fix_high_rounded, size: 15),
              label: const Text('补全缺失'),
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
        message: '暂无缓存作品\n访问作品或使用批量缓存后，会在这里显示。',
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
    final currentSelectedEntry = selected != null &&
            entries.any((e) => e.sourceId == selected.sourceId)
        ? entries.firstWhere((e) => e.sourceId == selected.sourceId)
        : null;

    final grid = LayoutBuilder(
      builder: (context, constraints) {
        const targetCardWidth = 176.0;
        const gap = 12.0;
        final columns = math
            .max(
              1,
              ((constraints.maxWidth + gap) / (targetCardWidth + gap)).floor(),
            )
            .toInt();
        final gridWidth = math
            .min(
              constraints.maxWidth,
              columns * targetCardWidth + (columns - 1) * gap + 24,
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
                mainAxisExtent: 354,
                crossAxisSpacing: gap,
                mainAxisSpacing: 14,
              ),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final isSelected = currentSelectedEntry?.sourceId == entry.sourceId;
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
              },
            ),
          ),
        );
      },
    );

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
            onPressed: () => ref.invalidate(cachedLibraryProvider),
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
    if (mounted) ref.invalidate(cachedLibraryProvider);
  }

  Future<void> _openCompleteMissing() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const CompleteMissingDialog(),
    );
    if (mounted) ref.invalidate(cachedLibraryProvider);
  }
}
