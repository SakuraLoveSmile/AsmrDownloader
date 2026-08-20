import 'package:asmr_downloader/pages/update/update_dialog.dart';
import 'package:asmr_downloader/services/update/update_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 版本号 + 检查更新入口：嵌入 Windows 自绘标题栏 / macOS 导航行。
///
/// 显示当前版本号；发现新版本时图标高亮提示，点击打开更新对话框；
/// 无已知新版时点击触发手动检查。
class UpdateEntry extends ConsumerWidget {
  const UpdateEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final version = ref.watch(appVersionProvider).valueOrNull ?? '';
    final updateState = ref.watch(latestUpdateProvider);
    final hasUpdate = updateState.valueOrNull != null;
    final checking = updateState.isLoading;
    final color = hasUpdate ? scheme.primary : scheme.onSurfaceVariant;

    return Tooltip(
      message: hasUpdate ? '发现新版本，点击更新' : '检查更新',
      child: InkWell(
        onTap: checking ? null : () => _onTap(context, ref, hasUpdate),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (checking)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                )
              else
                Icon(
                  hasUpdate ? Icons.system_update_alt : Icons.refresh,
                  size: 14,
                  color: color,
                ),
              if (version.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  'v$version',
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ],
              if (hasUpdate) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '新版本',
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onTap(
      BuildContext context, WidgetRef ref, bool hasUpdate) async {
    if (hasUpdate) {
      await showUpdateDialog(context);
      return;
    }
    final notifier = ref.read(latestUpdateProvider.notifier);
    final hasNew = await notifier.manualCheck();
    if (!context.mounted) return;
    if (hasNew) {
      await showUpdateDialog(context);
    }
    // 无新版/失败时 SnackBar 提示由 manualCheck 内部处理
  }
}
