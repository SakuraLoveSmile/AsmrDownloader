import 'package:asmr_downloader/pages/database/database.dart';
import 'package:asmr_downloader/pages/media_library/media_library.dart';
import 'package:asmr_downloader/services/cache/cache_library_providers.dart';
import 'package:asmr_downloader/services/database/database_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('数据库页面展示两个数据库的统计和表说明', (tester) async {
    const overview = DatabaseOverview(
      cachePath: '/tmp/asmr_cache.db',
      libraryPath: '/tmp/asmr_library.db',
      workInfoCount: 12,
      tracksCount: 10,
      coverCount: 8,
      libraryWorkCount: 3,
      libraryLocationCount: 5,
      libraryRootCount: 2,
    );
    final container = ProviderContainer(overrides: [
      databaseOverviewProvider.overrideWith((ref) async => overview),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: DatabasePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('数据库'), findsOneWidget);
    expect(find.text('元数据缓存数据库'), findsOneWidget);
    expect(find.text('媒体库索引数据库'), findsOneWidget);
    expect(find.text('/tmp/asmr_cache.db'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('database-overview')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    expect(find.text('数据表'), findsOneWidget);
  });

  testWidgets('媒体库可以切换按社团和 CV 分组', (tester) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final entries = [
      CachedLibraryEntry(
        sourceId: 'RJ10000001',
        cachedAt: DateTime(2026, 8, 22),
        workInfo: const {
          'title': '作品一',
          'circle': {'name': '社团甲'},
          'vas': [
            {'name': 'CV 甲'},
            {'name': 'CV 乙'},
          ],
        },
        hasTracks: true,
        hasCover: false,
      ),
      CachedLibraryEntry(
        sourceId: 'RJ10000002',
        cachedAt: DateTime(2026, 8, 21),
        workInfo: const {
          'title': '作品二',
          'circle': {'name': '社团甲'},
          'vas': [
            {'name': 'CV 乙'},
          ],
        },
        hasTracks: false,
        hasCover: false,
      ),
      CachedLibraryEntry(
        sourceId: 'RJ10000003',
        cachedAt: DateTime(2026, 8, 20),
        workInfo: const {'title': '作品三'},
        hasTracks: false,
        hasCover: false,
      ),
    ];
    final overrides = <Override>[
      cachedLibraryProvider.overrideWith((ref) async => CachedLibrary(entries)),
    ];
    for (final entry in entries) {
      overrides.add(
        cachedCoverProvider(entry.sourceId).overrideWith((ref) async => null),
      );
    }
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 900, height: 1000, child: MediaLibraryPage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final groupDropdown = find.byType(DropdownButton<MediaLibraryGroupBy>);
    expect(groupDropdown, findsOneWidget);
    await tester.tap(groupDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('按社团分类').last);
    await tester.pumpAndSettle();
    expect(find.text('社团甲'), findsOneWidget);
    expect(find.text('未关联社团'), findsOneWidget);

    await tester.tap(groupDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('按 CV 分类').last);
    await tester.pumpAndSettle();
    expect(find.text('CV 甲'), findsOneWidget);
    expect(find.text('CV 乙'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('media-library-grouped-list-cv')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    expect(find.text('未关联 CV'), findsOneWidget);
  });
}
