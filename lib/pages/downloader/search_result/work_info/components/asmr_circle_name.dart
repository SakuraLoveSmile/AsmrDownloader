import 'package:asmr_downloader/pages/components/copyable_textbox.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/work_info_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AsmrCircleName extends ConsumerWidget {
  const AsmrCircleName({super.key, required this.verticalPadding});
  final double verticalPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circleName = ref.watch(circleNameProvider).valueOrNull ?? '';
    final scheme = Theme.of(context).colorScheme;

    if (circleName.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: verticalPadding - 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.group_outlined,
            size: 14,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: CopyableTextBox(
              text: circleName,
              textStyle: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            ),
          ),
        ],
      ),
    );
  }
}
