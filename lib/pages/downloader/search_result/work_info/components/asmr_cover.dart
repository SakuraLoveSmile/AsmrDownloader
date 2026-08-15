import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:asmr_downloader/utils/log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transparent_image/transparent_image.dart';

class AsmrCover extends ConsumerWidget {
  const AsmrCover({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final coverLoadingState = ref.watch(coverLoadingStateProvider);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: coverLoadingState.when(
          data: (bytes) {
            if (bytes == null) {
              return _placeholder(scheme,
                  child: Icon(Icons.image_not_supported,
                      size: 40, color: scheme.onSurfaceVariant));
            }
            return FadeInImage(
                placeholder: MemoryImage(kTransparentImage),
                image: MemoryImage(bytes));
          },
          loading: () => _placeholder(
            scheme,
            child: const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.0),
            ),
          ),
          error: (error, stack) {
            Log.error('load cover image failed\n'
                'sourceId: ${ref.read(sourceIdProvider)}\n'
                'error: $error');
            return _placeholder(scheme,
                child: Icon(Icons.error, size: 40, color: scheme.error));
          },
        ),
      ),
    );
  }

  /// 加载/失败时的灰底占位（保持封面区域的宽高比）
  Widget _placeholder(ColorScheme scheme, {required Widget child}) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Container(
        color: scheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}
