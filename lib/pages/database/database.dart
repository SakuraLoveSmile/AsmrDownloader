import 'package:asmr_downloader/pages/media_library/components/cache_dialog.dart';
import 'package:asmr_downloader/services/database/database_providers.dart';
import 'package:asmr_downloader/ui/page_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 数据库页面：展示缓存数据库和媒体库索引数据库的状态。
///
/// 数据库仍由各自的服务负责读写，本页面只提供可读的概览和缓存管理入口，
/// 避免把数据库文件操作散落在媒体库工具栏里。
class DatabasePage extends ConsumerWidget {
  const DatabasePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(databaseOverviewProvider);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          icon: Icons.storage_rounded,
          title: '数据库',
          subtitle: '查看元数据缓存与媒体库扫描索引的状态',
          actions: [
            OutlinedButton.icon(
              key: const ValueKey('database-cache-management'),
              onPressed: () async {
                await showDialog<void>(
                  context: context,
                  builder: (_) => const CacheDialog(),
                );
                ref.invalidate(databaseOverviewProvider);
              },
              icon: const Icon(Icons.tune_rounded, size: 15),
              label: const Text('缓存管理'),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const ValueKey('database-refresh'),
              onPressed: () => ref.invalidate(databaseOverviewProvider),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              tooltip: '刷新数据库统计',
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                shape: const CircleBorder(),
                backgroundColor: scheme.surfaceContainerHigh.withValues(
                  alpha: 0.5,
                ),
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: overview.when(
            loading: () => const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (error, _) => _ErrorState(
              message: '读取数据库信息失败：$error',
              onRetry: () => ref.invalidate(databaseOverviewProvider),
            ),
            data: (data) => _OverviewContent(
              overview: data,
              onOpenCacheManagement: () async {
                await showDialog<void>(
                  context: context,
                  builder: (_) => const CacheDialog(),
                );
                ref.invalidate(databaseOverviewProvider);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _OverviewContent extends StatelessWidget {
  const _OverviewContent({
    required this.overview,
    required this.onOpenCacheManagement,
  });

  final DatabaseOverview overview;
  final VoidCallback onOpenCacheManagement;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('database-overview'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 26),
      children: [
        _buildSummary(context),
        const SizedBox(height: 16),
        _DatabaseCard(
          key: const ValueKey('database-cache-card'),
          icon: Icons.auto_awesome_motion_rounded,
          title: '元数据缓存数据库',
          subtitle: 'API 作品信息、音轨列表和封面缓存',
          path: overview.cachePath,
          metrics: [
            _DatabaseMetric(label: '作品信息', value: overview.workInfoCount),
            _DatabaseMetric(label: '音轨列表', value: overview.tracksCount),
            _DatabaseMetric(label: '封面', value: overview.coverCount),
          ],
          footer: OutlinedButton.icon(
            onPressed: onOpenCacheManagement,
            icon: const Icon(Icons.settings_outlined, size: 15),
            label: const Text('导入、导出或清理缓存'),
          ),
        ),
        const SizedBox(height: 12),
        _DatabaseCard(
          key: const ValueKey('database-library-card'),
          icon: Icons.account_tree_rounded,
          title: '媒体库索引数据库',
          subtitle: '扫描目录得到的 RJ / VJ / BJ 作品位置和状态',
          path: overview.libraryPath,
          metrics: [
            _DatabaseMetric(label: '作品索引', value: overview.libraryWorkCount),
            _DatabaseMetric(
              label: '扫描位置',
              value: overview.libraryLocationCount,
            ),
            _DatabaseMetric(label: '扫描目录', value: overview.libraryRootCount),
          ],
        ),
        const SizedBox(height: 16),
        _buildRelationCard(context),
        const SizedBox(height: 16),
        _buildTableCard(context),
      ],
    );
  }

  Widget _buildSummary(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final children = [
          _SummaryCard(
            icon: Icons.library_music_rounded,
            label: '媒体库扫描位置',
            value: '${overview.libraryLocationCount}',
            helper: '跨本机与 NAS 的已知位置',
          ),
          _SummaryCard(
            icon: Icons.description_rounded,
            label: '已缓存作品信息',
            value: '${overview.workInfoCount}',
            helper: '可关联标题、社团和 CV',
          ),
          _SummaryCard(
            icon: Icons.storage_rounded,
            label: '数据库文件',
            value: '2 个',
            helper: '缓存 + 媒体库索引',
          ),
        ];
        if (compact) {
          return Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1) const SizedBox(height: 8),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              Expanded(child: children[i]),
              if (i != children.length - 1) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }

  Widget _buildRelationCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _SectionCard(
      title: '数据关系',
      icon: Icons.hub_rounded,
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          _RelationNode(
            icon: Icons.folder_special_rounded,
            label: '扫描目录',
            detail: '只识别 RJ / VJ / BJ',
          ),
          Icon(Icons.arrow_forward_rounded,
              size: 18, color: scheme.onSurfaceVariant),
          _RelationNode(
            icon: Icons.account_tree_rounded,
            label: '媒体库索引',
            detail: '记录作品位置',
          ),
          Icon(Icons.add_rounded, size: 18, color: scheme.onSurfaceVariant),
          _RelationNode(
            icon: Icons.auto_awesome_motion_rounded,
            label: '元数据缓存',
            detail: '标题 / 社团 / CV / 封面',
          ),
        ],
      ),
    );
  }

  Widget _buildTableCard(BuildContext context) {
    return _SectionCard(
      title: '数据表',
      icon: Icons.table_chart_rounded,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: const [
          _TableChip(label: 'work_info_entries', detail: '作品信息'),
          _TableChip(label: 'tracks_entries', detail: '音轨列表'),
          _TableChip(label: 'cover_entries', detail: '封面 BLOB'),
          _TableChip(label: 'library_works', detail: '作品索引'),
          _TableChip(label: 'media_library_locations', detail: '扫描位置'),
          _TableChip(label: 'media_library_roots', detail: '扫描目录状态'),
        ],
      ),
    );
  }
}

class _DatabaseCard extends StatelessWidget {
  const _DatabaseCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.path,
    required this.metrics,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String path;
  final List<_DatabaseMetric> metrics;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 19, color: scheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 11.5)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: metrics,
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.folder_outlined,
                    size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: 7),
                Expanded(
                  child: SelectableText(
                    path,
                    maxLines: 2,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            if (footer != null) ...[
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: footer!),
            ],
          ],
        ),
      ),
    );
  }
}

class _DatabaseMetric extends StatelessWidget {
  const _DatabaseMetric({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 126),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant, width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value',
              style: TextStyle(
                  color: scheme.primary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.helper,
  });

  final IconData icon;
  final String label;
  final String value;
  final String helper;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant, width: 0.8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: scheme.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: scheme.onSurfaceVariant, fontSize: 11.5)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 1),
                Text(helper,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: scheme.onSurfaceVariant, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard(
      {required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: scheme.primary),
              const SizedBox(width: 7),
              Text(title,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _RelationNode extends StatelessWidget {
  const _RelationNode({
    required this.icon,
    required this.label,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant, width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: scheme.primary),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w600)),
              Text(detail,
                  style:
                      TextStyle(color: scheme.onSurfaceVariant, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TableChip extends StatelessWidget {
  const _TableChip({required this.label, required this.detail});

  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant, width: 0.7),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10.5),
          children: [
            TextSpan(
              text: label,
              style: TextStyle(
                color: scheme.onSurface,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(text: '  $detail'),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 40, color: scheme.error),
          const SizedBox(height: 10),
          Text(message, style: TextStyle(color: scheme.error)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
