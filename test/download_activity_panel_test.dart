import 'dart:io';

import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/pages/downloader/download_activity_panel.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/services/download/download_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  testWidgets('下载中心在没有搜索结果时仍显示当前作品的逐文件列表', (tester) async {
    final tempDir =
        Directory.systemTemp.createTempSync('download_activity_test');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final container = ProviderContainer(
      overrides: [
        downloadQueueFilePathProvider.overrideWithValue(
          p.join(tempDir.path, 'queue.json'),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(dlStatusProvider.notifier).state =
        DownloadStatus.downloading;
    container.read(currentDownloadingSourceIdProvider.notifier).state =
        'RJ12345678';
    container.read(downloadSegmentsProvider.notifier).state = [
      const DownloadSegment(
        title: 'voice-01.flac',
        size: 2048,
        fraction: 0.4,
        status: DownloadStatus.downloading,
        speed: 512,
      ),
    ];

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(body: DownloadActivityPanel()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('正在下载'), findsOneWidget);
    expect(find.text('RJ12345678'), findsOneWidget);
    expect(find.text('voice-01'), findsOneWidget);
    expect(find.byTooltip('取消下载'), findsOneWidget);
  });

  testWidgets('下载中心在没有搜索结果时仍显示待下载队列', (tester) async {
    final tempDir =
        Directory.systemTemp.createTempSync('download_queue_panel_test');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final container = ProviderContainer(
      overrides: [
        downloadQueueFilePathProvider.overrideWithValue(
          p.join(tempDir.path, 'queue.json'),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync<void>(() async {
      await container.read(downloadQueueProvider.notifier).add('RJ00000001');
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(body: DownloadActivityPanel()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('下载队列'), findsOneWidget);
    expect(find.text('RJ00000001'), findsOneWidget);
    expect(find.text('继续下载'), findsOneWidget);
  });
}
