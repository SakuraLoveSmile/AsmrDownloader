import 'package:asmr_downloader/pages/app_shell.dart';
import 'package:asmr_downloader/services/cache/cache_library_providers.dart';
import 'package:asmr_downloader/services/cache/cache_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:asmr_downloader/services/ui/ui_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transparent_image/transparent_image.dart';

/// 媒体库右侧非模态详情抽屉 (Inspector Panel)。
class WorkInspectorDrawer extends ConsumerWidget {
  const WorkInspectorDrawer({
    super.key,
    required this.entry,
    required this.onClose,
    this.onRemoved,
    this.onSelectTag,
    this.onSelectCv,
  });

  final CachedLibraryEntry entry;
  final VoidCallback onClose;
  final VoidCallback? onRemoved;
  final ValueChanged<String>? onSelectTag;
  final ValueChanged<String>? onSelectCv;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final cover = ref.watch(cachedCoverProvider(entry.sourceId));

    return Container(
      width: 350,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border:
            Border(left: BorderSide(color: scheme.outlineVariant, width: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部栏：sourceId + 关闭
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant, width: 0.6)),
            ),
            child: Row(
              children: [
                Text(
                  entry.sourceId,
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: -0.1,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: '关闭检查器',
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    shape: const CircleBorder(),
                    backgroundColor:
                        scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          // 内容区域
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 大封面
                  Center(
                    child: Container(
                      width: 220,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: scheme.outlineVariant, width: 0.8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11.4),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: cover.when(
                            loading: () => const Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                            error: (_, __) => Icon(
                              Icons.broken_image_outlined,
                              size: 40,
                              color: scheme.error,
                            ),
                            data: (bytes) => bytes == null
                                ? Icon(
                                    Icons.image_not_supported_outlined,
                                    size: 40,
                                    color: scheme.onSurfaceVariant,
                                  )
                                : FadeInImage(
                                    width: double.infinity,
                                    height: double.infinity,
                                    fit: BoxFit.cover,
                                    placeholder: MemoryImage(kTransparentImage),
                                    image: MemoryImage(bytes),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // 标题
                  SelectableText(
                    entry.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 快捷操作栏
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            await ref
                                .read(uiServiceProvider)
                                .search(entry.sourceId);
                            // 切换到下载 Tab
                            ref.read(currentNavTabProvider.notifier).state = 0;
                          },
                          icon: const Icon(Icons.download_rounded, size: 15),
                          label: const Text('前往下载',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(
                              text: '${entry.sourceId} ${entry.title}'));
                          showAppSnackBar(context, '已复制作品信息');
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        tooltip: '复制标题与ID',
                        style: IconButton.styleFrom(
                          shape: const CircleBorder(),
                          backgroundColor: scheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 14),
                  // 元数据项目
                  _InfoItem(
                    label: '社团',
                    content: entry.circleName.isEmpty
                        ? const Text('-')
                        : InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () => onSelectCv?.call(entry.circleName),
                            child: Text(
                              entry.circleName,
                              style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  _InfoItem(
                    label: 'CV / 声优',
                    content: entry.cvNames.isEmpty
                        ? const Text('-')
                        : Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final cv in entry.cvNames)
                                InkWell(
                                  borderRadius: BorderRadius.circular(100),
                                  onTap: () => onSelectCv?.call(cv),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: scheme.primary
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(100),
                                      border: Border.all(
                                        color: scheme.primary
                                            .withValues(alpha: 0.3),
                                        width: 0.6,
                                      ),
                                    ),
                                    child: Text(
                                      cv,
                                      style: TextStyle(
                                        color: scheme.primary,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 8),
                  _InfoItem(
                    label: '发售日期',
                    content: Text(
                        entry.releaseDate.isEmpty ? '-' : entry.releaseDate),
                  ),
                  const SizedBox(height: 8),
                  _InfoItem(
                    label: '销量',
                    content: Text(entry.dlCount.isEmpty ? '-' : entry.dlCount),
                  ),
                  const SizedBox(height: 8),
                  _InfoItem(
                    label: '缓存时间',
                    content: Text(_formatDateTime(entry.cachedAt)),
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  // 标签云
                  Text(
                    '标签 (${entry.tags.length})',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (entry.tags.isEmpty)
                    Text('-', style: TextStyle(color: scheme.onSurfaceVariant))
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tag in entry.tags)
                          ActionChip(
                            label: Text(tag,
                                style: const TextStyle(fontSize: 11.5)),
                            padding: EdgeInsets.zero,
                            shape: const StadiumBorder(),
                            backgroundColor: scheme.surfaceContainerLow,
                            side: BorderSide(
                                color: scheme.outlineVariant, width: 0.6),
                            onPressed: () => onSelectTag?.call(tag),
                          ),
                      ],
                    ),
                  const SizedBox(height: 20),
                  // 删除缓存
                  Center(
                    child: TextButton.icon(
                      onPressed: () => _confirmRemove(context, ref),
                      icon: Icon(Icons.delete_outline_rounded,
                          size: 16, color: scheme.error),
                      label: Text('删除该条本地缓存',
                          style: TextStyle(color: scheme.error, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除缓存条目'),
        content: Text('将删除 ${entry.sourceId} 的元数据与封面缓存。确定继续吗？'),
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
    if (confirmed != true) return;

    try {
      await ref.read(cacheServiceProvider).removeEntry(entry.sourceId);
      ref.invalidate(cachedLibraryProvider);
      ref.invalidate(cachedCoverProvider(entry.sourceId));
      onRemoved?.call();
      onClose();
      if (context.mounted) {
        showAppSnackBar(context, '已删除缓存：${entry.sourceId}');
      }
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, '删除缓存失败：$e');
      }
    }
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({required this.label, required this.content});

  final String label;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(child: content),
      ],
    );
  }
}
