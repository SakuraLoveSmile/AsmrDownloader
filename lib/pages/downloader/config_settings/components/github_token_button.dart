import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// GitHub Token 设置入口（可选配置）：
/// 更新检查与 AI 引擎安装的 GitHub API 请求带认证后，
/// 限额从匿名 60 次/小时/IP 提升到 5000 次/小时/账号，
/// 共享代理出口 IP 也不会触发限流。
class GithubTokenButton extends ConsumerWidget {
  const GithubTokenButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final hasToken = ref.watch(githubTokenProvider).isNotEmpty;
    return Tooltip(
      message: hasToken ? 'GitHub Token 已配置' : 'GitHub Token（可选，避免 API 限流）',
      child: IconButton(
        onPressed: () => _showTokenDialog(context, ref),
        icon: Icon(
          Icons.key,
          size: 16,
          color: hasToken ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Future<void> _showTokenDialog(BuildContext context, WidgetRef ref) async {
    final controller =
        TextEditingController(text: ref.read(githubTokenProvider));
    final obscure = ValueNotifier<bool>(true);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => ValueListenableBuilder<bool>(
        valueListenable: obscure,
        builder: (context, hidden, _) => AlertDialog(
          title: const Text('GitHub Token（可选）'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '填入 GitHub Personal Access Token 后，更新检查与 AI 引擎'
                  '安装的 GitHub API 请求将带认证：限额从匿名 60 次/小时/IP '
                  '提升到 5000 次/小时/账号，共享代理出口也不会触发限流。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '仅用于读取公开仓库信息，生成时无需勾选任何权限。\n'
                  '前往 github.com/settings/tokens 生成'
                  '（Fine-grained / classic 均可）。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  obscureText: hidden,
                  decoration: InputDecoration(
                    labelText: 'Personal Access Token',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        hidden ? Icons.visibility : Icons.visibility_off,
                        size: 18,
                      ),
                      onPressed: () => obscure.value = !hidden,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('clear'),
              child: const Text('清除'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('save'),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    final entered = controller.text;
    controller.dispose();
    obscure.dispose();
    if (result == 'save') {
      ref.read(uiServiceProvider).setGithubToken(entered);
    } else if (result == 'clear') {
      ref.read(uiServiceProvider).setGithubToken('');
    }
  }
}
