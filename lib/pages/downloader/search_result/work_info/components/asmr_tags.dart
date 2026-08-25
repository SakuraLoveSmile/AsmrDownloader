import 'package:asmr_downloader/pages/components/copyable_textbox.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/work_info_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AsmrTags extends ConsumerWidget {
  const AsmrTags({super.key, required this.verticalPadding});
  final double verticalPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final tagLs = ref.watch(tagLsProvider);
    if (tagLs.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: verticalPadding),
      child: Wrap(
        alignment: WrapAlignment.start,
        spacing: 6.0,
        runSpacing: 6.0,
        children: [
          ...tagLs.map((e) => CopyableTextBox(
                text: e,
                textStyle: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.85),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
                backgroundColor:
                    scheme.surfaceContainerHigh.withValues(alpha: 0.6),
                border: Border.all(color: scheme.outlineVariant, width: 0.8),
                borderRadius: 100.0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10.0, vertical: 3.0),
              ))
        ],
      ),
    );
  }
}
