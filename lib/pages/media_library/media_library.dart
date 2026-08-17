import 'dart:math' as math;

import 'package:asmr_downloader/pages/library/tools/cache_dialog.dart';
import 'package:asmr_downloader/pages/media_library/components/cached_work_card.dart';
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 280,
            child: TextField(
              controller: _searchController,
              onChanged: (value) =>
                  ref.read(cacheSearchQueryProvider.notifier).state = value,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: '搜索 sourceId / 标题 / 社团 / CV',
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          ref.read(cacheSearchQueryProvider.notifier).state =
                              '';
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear, size: 17),
                        tooltip: '清除搜索',
                        visualDensity: VisualDensity.compact,
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          _buildSortSelector(sort),
          Text(
            '共 ${total ?? '…'} 条 / 命中 ${matched ?? '…'} 条',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          IconButton(
            onPressed: () => ref.invalidate(cachedLibraryProvider),
            icon: const Icon(Icons.refresh, size: 19),
            tooltip: '刷新媒体库',
            visualDensity: VisualDensity.compact,
          ),
          OutlinedButton.icon(
            onPressed: _openCacheManagement,
            icon: const Icon(Icons.settings_outlined, size: 17),
            label: const Text('缓存管理'),
          ),
        ],
      ),
    );
  }

  Widget _buildSortSelector(CacheSort sort) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<CacheSort>(
          value: sort,
          isDense: true,
          icon: const Icon(Icons.unfold_more, size: 17),
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

    return LayoutBuilder(
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
              itemBuilder: (context, index) => CachedWorkCard(
                entry: entries[index],
                onRemoved: () => setState(() {}),
              ),
            ),
          ),
        );
      },
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
}
