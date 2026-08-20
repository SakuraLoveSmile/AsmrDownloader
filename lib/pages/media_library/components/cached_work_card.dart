import 'package:asmr_downloader/services/cache/cache_library_providers.dart';
import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transparent_image/transparent_image.dart';

class CachedWorkCard extends ConsumerStatefulWidget {
  const CachedWorkCard({
    super.key,
    required this.entry,
    this.isSelected = false,
    this.onTap,
    this.onRemoved,
  });

  final CachedLibraryEntry entry;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onRemoved;

  @override
  ConsumerState<CachedWorkCard> createState() => _CachedWorkCardState();
}

class _CachedWorkCardState extends ConsumerState<CachedWorkCard> {
  bool _hovered = false;
  bool _removing = false;

  CachedLibraryEntry get entry => widget.entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = widget.isSelected;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primary.withValues(alpha: 0.12)
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? scheme.primary
                : _hovered
                    ? scheme.primary.withValues(alpha: 0.4)
                    : scheme.outlineVariant,
            width: isSelected ? 1.4 : 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? scheme.primary.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: _hovered ? 0.35 : 0.12),
              blurRadius: _hovered || isSelected ? 16 : 6,
              offset: Offset(0, _hovered ? 6 : 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap ?? _showDetails,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCover(scheme),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 36,
                        child: Text(
                          entry.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        entry.sourceId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.primary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _secondaryLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.releaseDate.isEmpty ? '发售日期：-' : entry.releaseDate,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 14,
                  left: 14,
                  child: _buildCacheBadges(scheme),
                ),
                if (_hovered || _removing)
                  Positioned(
                    top: 14,
                    right: 14,
                    child: _buildActions(scheme),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _secondaryLine {
    final circle = entry.circleName;
    final cvs = entry.cvNames.join('、');
    if (circle.isEmpty && cvs.isEmpty) return '社团/CV：-';
    if (circle.isEmpty) return 'CV：$cvs';
    if (cvs.isEmpty) return circle;
    return '$circle · $cvs';
  }

  Widget _buildCover(ColorScheme scheme) {
    final cover = ref.watch(cachedCoverProvider(entry.sourceId));
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant, width: 0.6),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9.4),
          child: cover.when(
            loading: () => _placeholder(
              scheme,
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.primary,
                ),
              ),
            ),
            error: (_, __) => _placeholder(
              scheme,
              Icon(Icons.broken_image_outlined, size: 30, color: scheme.error),
            ),
            data: (bytes) => bytes == null
                ? _placeholder(
                    scheme,
                    Icon(Icons.image_not_supported_outlined,
                        size: 32, color: scheme.onSurfaceVariant),
                  )
                : FadeInImage(
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.contain,
                    placeholder: MemoryImage(kTransparentImage),
                    image: MemoryImage(bytes),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme, Widget child) {
    return Container(
      color: scheme.surfaceContainerLow,
      alignment: Alignment.center,
      child: child,
    );
  }

  Widget _buildCacheBadges(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xE01C1C1E),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: scheme.outlineVariant, width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CacheBadge(
            icon: Icons.headphones_rounded,
            present: entry.hasTracks,
            tooltip: entry.hasTracks ? '已缓存 tracks' : '缺少 tracks',
          ),
          const SizedBox(width: 4),
          _CacheBadge(
            icon: Icons.image_rounded,
            present: entry.hasCover,
            tooltip: entry.hasCover ? '已缓存封面' : '缺少封面',
          ),
        ],
      ),
    );
  }

  Widget _buildActions(ColorScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xE01C1C1E),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: scheme.outlineVariant, width: 0.6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: _removing ? null : _showDetails,
            icon: const Icon(Icons.info_outline_rounded, size: 16),
            tooltip: '查看详情',
            visualDensity: VisualDensity.compact,
            splashRadius: 14,
          ),
          IconButton(
            onPressed: _removing ? null : _remove,
            icon: _removing
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.error,
                    ),
                  )
                : Icon(Icons.delete_outline_rounded, size: 16, color: scheme.error),
            tooltip: '删除该条缓存',
            visualDensity: VisualDensity.compact,
            splashRadius: 14,
          ),
        ],
      ),
    );
  }

  Future<void> _showDetails() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CachedWorkDetailsDialog(entry: entry),
    );
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除缓存条目'),
        content: Text('将删除 ${entry.sourceId} 的 workInfo、tracks 和封面缓存。确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _removing = true);
    try {
      await ref.read(cacheServiceProvider).removeEntry(entry.sourceId);
      ref.invalidate(cachedLibraryProvider);
      ref.invalidate(cachedCoverProvider(entry.sourceId));
      widget.onRemoved?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除缓存：${entry.sourceId}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除缓存失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }
}

class _CacheBadge extends StatelessWidget {
  const _CacheBadge({
    required this.icon,
    required this.present,
    required this.tooltip,
  });

  final IconData icon;
  final bool present;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(
            present ? icon : Icons.remove_circle_outline,
            size: 13,
            color: present ? scheme.primary : scheme.error,
          ),
        ),
      ),
    );
  }
}

class _CachedWorkDetailsDialog extends StatelessWidget {
  const _CachedWorkDetailsDialog({required this.entry});

  final CachedLibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(entry.title),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(label: 'sourceId', value: entry.sourceId),
              _DetailRow(label: '社团', value: _orDash(entry.circleName)),
              _DetailRow(label: 'CV', value: _orDash(entry.cvNames.join('、'))),
              _DetailRow(label: '发售日期', value: _orDash(entry.releaseDate)),
              _DetailRow(label: 'dl_count', value: _orDash(entry.dlCount)),
              _DetailRow(label: '缓存时间', value: _formatDateTime(entry.cachedAt)),
              const SizedBox(height: 8),
              Text('标签', style: theme.textTheme.labelMedium),
              const SizedBox(height: 5),
              if (entry.tags.isEmpty)
                Text('-', style: theme.textTheme.bodyMedium)
              else
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    for (final tag in entry.tags)
                      Chip(
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

String _orDash(String value) => value.isEmpty ? '-' : value;

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}
