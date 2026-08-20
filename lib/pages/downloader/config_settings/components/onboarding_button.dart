import 'package:asmr_downloader/pages/onboarding/onboarding_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 「新手引导」入口按钮：重新启动交互式新手引导，
/// 在真实界面上高亮各功能元素并逐步讲解。
class OnboardingButton extends ConsumerWidget {
  const OnboardingButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Tooltip(
      message: '重新查看新手引导（高亮各功能元素并逐步讲解）',
      child: OutlinedButton.icon(
        onPressed: () => startOnboarding(ProviderScope.containerOf(context)),
        icon: const Icon(Icons.waving_hand_outlined, size: 14),
        label: const Text('新手引导'),
      ),
    );
  }
}
