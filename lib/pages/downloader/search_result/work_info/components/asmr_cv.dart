import 'package:asmr_downloader/pages/components/copyable_textbox.dart';
import 'package:asmr_downloader/services/asmr_repo/providers/work_info_providers.dart';
import 'package:asmr_downloader/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AsmrCv extends ConsumerWidget {
  const AsmrCv({super.key, required this.verticalPadding});

  final double verticalPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cvLs = ref.watch(cvLsProvider);
    if (cvLs.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: verticalPadding, bottom: verticalPadding),
      child: Wrap(
        alignment: WrapAlignment.start,
        spacing: 6.0,
        runSpacing: 6.0,
        children: [
          ...cvLs.map((e) => CopyableTextBox(
                text: 'CV: $e',
                textStyle: const TextStyle(
                  color: AppColors.cvText,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
                backgroundColor: AppColors.cvBg,
                border: Border.all(
                  color: AppColors.cvText.withValues(alpha: 0.25),
                  width: 0.8,
                ),
                borderRadius: 100.0,
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 3.0),
              ))
        ],
      ),
    );
  }
}
