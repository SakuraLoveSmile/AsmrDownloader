import 'package:asmr_downloader/services/library/work_library_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 搜索作品的入库状态徽章：已入库（本机/媒体库）或未入库。
///
/// 检测失败或未搜索时静默隐藏，不干扰作品信息展示。
class AsmrLibraryStatus extends ConsumerWidget {
  const AsmrLibraryStatus({super.key, this.verticalPadding = 10.0});
  final double verticalPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final statusAsync = ref.watch(workLibraryStatusProvider);

    return Padding(
      padding: EdgeInsets.only(top: verticalPadding),
      child: statusAsync.when(
        data: (status) => status == null
            ? const SizedBox.shrink()
            : _StatusChip(status: status),
        loading: () => _Chip(
          icon: SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
          label: '正在检测入库状态…',
        ),
        error: (error, stackTrace) => const SizedBox.shrink(),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final WorkLibraryStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inLibrary = status.inLibrary;

    final sources = <String>[
      if (status.localPaths.isNotEmpty) '本机',
      if (status.externalLocations.isNotEmpty) '媒体库',
    ];

    final tooltipLines = <String>[
      if (status.localPaths.isNotEmpty) ...[
        '本机副本：',
        for (final path in status.localPaths) '  $path',
      ],
      if (status.externalLocations.isNotEmpty) ...[
        '媒体库副本（下载时会跳过重复下载）：',
        for (final location in status.externalLocations)
          '  ${location.matchedPath}',
      ],
      if (!inLibrary) '本机下载目录与媒体库扫描记录中均未发现该作品',
    ];

    return Tooltip(
      message: tooltipLines.join('\n'),
      waitDuration: const Duration(milliseconds: 300),
      child: _Chip(
        icon: Icon(
          inLibrary
              ? Icons.task_alt_rounded
              : Icons.check_circle_outline_rounded,
          size: 14,
          color: inLibrary
              ? scheme.primary
              : scheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
        label: inLibrary ? '已入库 · ${sources.join(' + ')}' : '未入库',
        inLibrary: inLibrary,
      ),
    );
  }
}

/// 统一的胶囊样式（与媒体库页面的计数胶囊一致）。
class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    this.inLibrary = false,
  });

  final Widget icon;
  final String label;
  final bool inLibrary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: inLibrary
            ? scheme.primaryContainer.withValues(alpha: 0.55)
            : scheme.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: inLibrary
              ? scheme.primary.withValues(alpha: 0.45)
              : scheme.outlineVariant,
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: inLibrary
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
