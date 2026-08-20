import 'package:asmr_downloader/services/asmr_repo/providers/work_info_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AsmrMiscInfo extends ConsumerWidget {
  const AsmrMiscInfo({super.key, required this.verticalPadding});
  final double verticalPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final releaseDate = ref.watch(releaseDateProvider);
    final dlCount = ref.watch(dlCountProvider);

    final metaStyle = TextStyle(
      fontSize: 12,
      color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
      fontWeight: FontWeight.w400,
    );

    return Padding(
      padding: EdgeInsets.only(top: verticalPadding - 2),
      child: Row(
        children: [
          if (releaseDate.isNotEmpty) ...[
            Icon(
              Icons.calendar_today_outlined,
              size: 13,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 4),
            Text(releaseDate, style: metaStyle),
            const SizedBox(width: 14),
          ],
          if (dlCount > 0) ...[
            Icon(
              Icons.shopping_bag_outlined,
              size: 13,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 4),
            Text('销量 $dlCount', style: metaStyle),
          ],
        ],
      ),
    );
  }
}
