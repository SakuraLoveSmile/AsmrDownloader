import 'package:asmr_downloader/pages/components/copyable_textbox.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/work_info_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AsmrTitle extends ConsumerWidget {
  const AsmrTitle({super.key, required this.verticalPadding});
  final double verticalPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = ref.watch(titleProvider);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(top: verticalPadding + 2),
      child: CopyableTextBox(
        text: title,
        textStyle: TextStyle(
          fontSize: 16.5,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
          height: 1.35,
          letterSpacing: -0.2,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      ),
    );
  }
}
