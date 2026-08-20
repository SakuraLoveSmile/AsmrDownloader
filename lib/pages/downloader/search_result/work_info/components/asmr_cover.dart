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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 330),
      child: Center(
        child: AspectRatio(
          aspectRatio: 3 / 4,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outlineVariant, width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13.2),
              child: coverLoadingState.when(
                data: (bytes) {
                  if (bytes == null) {
                    return _placeholder(
                      scheme,
                      child: Icon(Icons.image_not_supported_outlined,
                          size: 42, color: scheme.onSurfaceVariant),
                    );
                  }
                  return FadeInImage(
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.contain,
                    placeholder: MemoryImage(kTransparentImage),
                    image: MemoryImage(bytes),
                  );
                },
                loading: () => _placeholder(
                  scheme,
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      color: scheme.primary,
                    ),
                  ),
                ),
                error: (error, stack) {
                  Log.error('load cover image failed\n'
                      'sourceId: ${ref.read(sourceIdProvider)}\n'
                      'error: $error');
                  return _placeholder(
                    scheme,
                    child: Icon(Icons.broken_image_outlined,
                        size: 42, color: scheme.error),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 加载/失败时的灰底占位（保持封面区域的宽高比）
  Widget _placeholder(ColorScheme scheme, {required Widget child}) {
    return Container(
      color: scheme.surfaceContainerLow,
      alignment: Alignment.center,
      child: child,
    );
  }
}
