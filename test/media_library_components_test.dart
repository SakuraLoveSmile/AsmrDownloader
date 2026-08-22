import 'package:asmr_downloader/pages/media_library/components/cached_work_card.dart';
import 'package:asmr_downloader/pages/media_library/components/work_inspector_drawer.dart';
import 'package:asmr_downloader/services/cache/cache_library_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transparent_image/transparent_image.dart';

void main() {
  final entry = CachedLibraryEntry(
    sourceId: 'RJ700002',
    cachedAt: DateTime(2026, 8, 21),
    workInfo: const {'title': '测试标题'},
    hasTracks: true,
    hasCover: true,
  );

  ProviderContainer makeContainer() {
    return ProviderContainer(overrides: [
      cachedCoverProvider(entry.sourceId)
          .overrideWith((ref) async => kTransparentImage),
    ]);
  }

  testWidgets('媒体库卡片封面为方形并铺满显示', (tester) async {
    final container = makeContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 220,
              child: CachedWorkCard(entry: entry, onTap: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final image = tester.widget<FadeInImage>(find.byType(FadeInImage));
    expect(image.fit, BoxFit.cover);
    final coverSize = tester.getSize(find.byType(AspectRatio));
    expect(coverSize.width, coverSize.height);
  });

  testWidgets('媒体库卡片显示原版社团和翻译社团', (tester) async {
    final translated = CachedLibraryEntry(
      sourceId: 'RJ700003',
      cachedAt: DateTime(2026, 8, 21),
      workInfo: const {
        'title': '简体中文版作品',
        'circle': {'name': '中文翻译组'},
      },
      resolvedCircleName: '日文原版社团',
      translationCircleName: '中文翻译组',
      hasTracks: true,
      hasCover: true,
    );
    final container = ProviderContainer(overrides: [
      cachedCoverProvider(translated.sourceId)
          .overrideWith((ref) async => kTransparentImage),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 220,
              child: CachedWorkCard(entry: translated, onTap: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('日文原版社团 · 翻译：中文翻译组'), findsOneWidget);
  });

  testWidgets('媒体库详情封面为方形并铺满显示', (tester) async {
    final container = makeContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 350,
              height: 720,
              child: WorkInspectorDrawer(
                entry: entry,
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final image = tester.widget<FadeInImage>(find.byType(FadeInImage));
    expect(image.fit, BoxFit.cover);
    final coverSize = tester.getSize(find.byType(AspectRatio));
    expect(coverSize.width, coverSize.height);
  });
}
