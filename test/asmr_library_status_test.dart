import 'dart:async';

import 'package:asmr_downloader/pages/downloader/search_result/work_info/components/asmr_library_status.dart';
import 'package:asmr_downloader/services/library/media_library_service.dart';
import 'package:asmr_downloader/services/library/work_library_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

MediaLibraryLocationItem _location(String sourceId, String path) {
  return MediaLibraryLocationItem(
    sourceId: sourceId,
    rootPath: '/nas',
    matchedPath: path,
    depth: 2,
    scannedAt: DateTime(2026, 8, 24),
  );
}

Future<void> _pumpStatus(
  WidgetTester tester,
  Override override,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [override],
      child: const MaterialApp(
        home: Scaffold(body: AsmrLibraryStatus()),
      ),
    ),
  );
  // 第一帧为检测中，异步结果就绪后再泵一帧渲染徽章
  await tester.pump();
}

void main() {
  testWidgets('本机与媒体库都有副本时展示完整来源', (tester) async {
    await _pumpStatus(
      tester,
      workLibraryStatusProvider.overrideWith(
        (ref) async => WorkLibraryStatus(
          localPaths: const ['/dl/CV-标题/RJ01619789'],
          externalLocations: [_location('RJ01619789', '/nas/社团/RJ01619789')],
        ),
      ),
    );

    expect(find.text('已入库 · 本机 + 媒体库'), findsOneWidget);
    expect(find.byIcon(Icons.task_alt_rounded), findsOneWidget);
  });

  testWidgets('仅有 NAS 副本时展示媒体库来源', (tester) async {
    await _pumpStatus(
      tester,
      workLibraryStatusProvider.overrideWith(
        (ref) async => WorkLibraryStatus(
          localPaths: const [],
          externalLocations: [_location('RJ01619789', '/nas/社团/RJ01619789')],
        ),
      ),
    );

    expect(find.text('已入库 · 媒体库'), findsOneWidget);
  });

  testWidgets('无副本时展示未入库', (tester) async {
    await _pumpStatus(
      tester,
      workLibraryStatusProvider.overrideWith(
        (ref) async => const WorkLibraryStatus(
          localPaths: [],
          externalLocations: [],
        ),
      ),
    );

    expect(find.text('未入库'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
  });

  testWidgets('检测期间展示检测中提示，未搜索时隐藏', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workLibraryStatusProvider.overrideWith((ref) => Completer<WorkLibraryStatus?>().future),
        ],
        child: const MaterialApp(
          home: Scaffold(body: AsmrLibraryStatus()),
        ),
      ),
    );
    expect(find.text('正在检测入库状态…'), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workLibraryStatusProvider.overrideWith((ref) async => null),
        ],
        child: const MaterialApp(
          home: Scaffold(body: AsmrLibraryStatus()),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Tooltip), findsNothing);
  });
}
