import 'dart:io';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/library/cv_stats_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// CV 统计与头像管理对话框。
///
/// 顶部为头像目录管理与 Navidrome 配置提示，主体为 CV 列表（专辑数/歌曲数
/// 聚合 + 圆形头像 + 设置/清除/查看作品操作），呼应 Navidrome 的占位风格。
class CvStatsDialog extends ConsumerWidget {
  const CvStatsDialog({super.key, required this.onViewWorks});

  /// 关闭对话框并把 CV 名填入媒体库搜索框（复用 `_applyFilter`）。
  final void Function(String cvName) onViewWorks;

  static const _imageExts = ['jpg', 'jpeg', 'png', 'webp', 'gif'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final dir = ref.watch(cvAvatarPathProvider).trim();
    final indexAsync = ref.watch(cvAvatarIndexProvider);
    final statsAsync = ref.watch(cvStatsProvider);

    final configText = dir.isEmpty
        ? 'ArtistImageFolder = <未设置目录>'
        : "ArtistImageFolder = '$dir'\n"
            "ArtistArtPriority = 'artist.*, album/artist.*, image-folder, external'";

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.person_search_rounded, color: scheme.primary, size: 20),
          const SizedBox(width: 8),
          const Text('CV 统计与头像管理'),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: '关闭',
            visualDensity: VisualDensity.compact,
            splashRadius: 16,
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      content: SizedBox(
        width: 680,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDirRow(context, ref, dir),
            const SizedBox(height: 10),
            _buildNavidromeHint(context, ref, configText),
            const SizedBox(height: 10),
            _buildSummaryChip(context, statsAsync, indexAsync),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 6),
            Expanded(
              child: statsAsync.when(
                loading: () => const Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (error, _) => Center(
                  child: Text('加载 CV 统计失败：$error',
                      style: TextStyle(color: scheme.error)),
                ),
                data: (stats) =>
                    _buildList(context, ref, dir, stats, indexAsync),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirRow(BuildContext context, WidgetRef ref, String dir) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Expanded(
          child: dir.isEmpty
              ? Text(
                  '尚未设置 CV 头像目录',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                  ),
                )
              : SelectableText(
                  dir,
                  style: TextStyle(fontSize: 12.5, color: scheme.onSurface),
                ),
        ),
        OutlinedButton.icon(
          onPressed: () => ref.read(uiServiceProvider).pickCvAvatarPath(),
          icon: const Icon(Icons.folder_open_rounded, size: 15),
          label: const Text('选择目录'),
        ),
        OutlinedButton.icon(
          onPressed: dir.isEmpty
              ? null
              : () => ref.read(uiServiceProvider).openFolderForDir(dir),
          icon: const Icon(Icons.open_in_new_rounded, size: 15),
          label: const Text('打开目录'),
        ),
      ],
    );
  }

  Widget _buildNavidromeHint(
    BuildContext context,
    WidgetRef ref,
    String configText,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant, width: 0.7),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.settings_ethernet_rounded,
                  size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              const Text('Navidrome 配置（写入 config.toml）',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: configText));
                  ref.read(uiServiceProvider).showSnack('已复制配置');
                },
                icon: const Icon(Icons.copy_rounded, size: 15),
                tooltip: '复制',
                visualDensity: VisualDensity.compact,
                splashRadius: 16,
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            configText,
            style: TextStyle(
              fontSize: 11.5,
              fontFamily: 'monospace',
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'image-folder 排在 external（Last.fm）之前 = 手动头像优先；'
            '想把知名 CV 的 Last.fm 头像排在手动头像之前，把 image-folder 移到 external 后面即可。',
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryChip(
    BuildContext context,
    AsyncValue<List<CvStat>> statsAsync,
    AsyncValue<Map<String, String>> indexAsync,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final total = statsAsync.valueOrNull?.length ?? 0;
    final index = indexAsync.valueOrNull;
    final setCount = (statsAsync.valueOrNull == null || index == null)
        ? 0
        : statsAsync.valueOrNull!
            .where((s) => findCvAvatarPath(index, s.name) != null)
            .length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: scheme.outlineVariant, width: 0.6),
      ),
      child: Text(
        '共 $total 位 CV · 已设置头像 $setCount',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    String dir,
    List<CvStat> stats,
    AsyncValue<Map<String, String>> indexAsync,
  ) {
    if (stats.isEmpty) {
      final scheme = Theme.of(context).colorScheme;
      return Center(
        child: Text(
          '暂无已关联 CV 的作品',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        ),
      );
    }

    final index = indexAsync.valueOrNull ?? const {};
    final scheme = Theme.of(context).colorScheme;

    return ListView.separated(
      itemCount: stats.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final stat = stats[i];
        final avatarPath = findCvAvatarPath(index, stat.name);
        final hasAvatar = avatarPath != null;

        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: scheme.surfaceContainerHighest,
            backgroundImage:
                hasAvatar ? FileImage(File(avatarPath)) : null,
            child: hasAvatar
                ? null
                : Icon(Icons.star_rounded,
                    color: scheme.onSurfaceVariant, size: 22),
          ),
          title: Text(stat.name,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Text(
            '${stat.albumCount} 张专辑 · ${stat.trackCount} 首歌曲',
            style:
                TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
          trailing: Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: dir.isEmpty
                    ? null
                    : () => _pickAvatar(context, ref, dir, stat.name),
                icon: const Icon(Icons.add_photo_alternate_rounded, size: 14),
                label: const Text('设置头像'),
                style: _miniButtonStyle(),
              ),
              if (hasAvatar)
                OutlinedButton.icon(
                  onPressed: () => _clearAvatar(ref, dir, stat.name),
                  icon: const Icon(Icons.delete_outline_rounded, size: 14),
                  label: const Text('清除'),
                  style: _miniButtonStyle(),
                ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  onViewWorks(stat.name);
                },
                icon: const Icon(Icons.visibility_rounded, size: 14),
                label: const Text('查看作品'),
                style: _miniButtonStyle(),
              ),
            ],
          ),
        );
      },
    );
  }

  ButtonStyle _miniButtonStyle() => const ButtonStyle(
        visualDensity: VisualDensity(horizontal: -2, vertical: -2),
        textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11.5)),
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
      );

  Future<void> _pickAvatar(
    BuildContext context,
    WidgetRef ref,
    String dir,
    String cvName,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _imageExts,
    );
    final path = firstPickedImagePath(result);
    if (path == null) return;
    await ref.read(setCvAvatarProvider((
      dir: dir,
      cvName: cvName,
      sourceFile: path,
    )).future);
    if (context.mounted) {
      ref.read(uiServiceProvider).showSnack('已设置头像：$cvName');
    }
  }

  Future<void> _clearAvatar(WidgetRef ref, String dir, String cvName) async {
    await ref.read(clearCvAvatarProvider((
      dir: dir,
      cvName: cvName,
    )).future);
    ref.read(uiServiceProvider).showSnack('已清除头像：$cvName');
  }
}
