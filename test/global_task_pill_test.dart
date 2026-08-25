import 'package:asmr_downloader/pages/app_shell.dart';
import 'package:asmr_downloader/services/download/download_queue.dart';
import 'package:asmr_downloader/services/tasks/background_task_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('无下载与后台任务时 TaskPill 隐藏', (tester) async {
    final container = ProviderContainer(
      overrides: [
        currentDownloadingSourceIdProvider.overrideWith((ref) => null),
        backgroundTaskProvider
            .overrideWith(() => _FakeBackgroundTaskNotifier([])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: AppShell(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(const ValueKey('global-task-pill')), findsNothing);
  });

  testWidgets('正在下载时展示 TaskPill，点击跳转下载列表页', (tester) async {
    final container = ProviderContainer(
      overrides: [
        currentDownloadingSourceIdProvider.overrideWith((ref) => 'RJ123456'),
        backgroundTaskProvider
            .overrideWith(() => _FakeBackgroundTaskNotifier([])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: AppShell(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final pillFinder = find.byKey(const ValueKey('global-task-pill'));
    expect(pillFinder, findsOneWidget);
    expect(find.text('正在下载 RJ123456'), findsOneWidget);

    await tester.tap(pillFinder);
    await tester.pump();

    expect(container.read(currentPageProvider), AppPageIndex.downloadList);
  });

  testWidgets('有后台任务时展示 TaskPill，点击跳转后台任务页', (tester) async {
    final container = ProviderContainer(
      overrides: [
        currentDownloadingSourceIdProvider.overrideWith((ref) => null),
        backgroundTaskProvider.overrideWith(() => _FakeBackgroundTaskNotifier([
              BackgroundTask(
                id: 'task-1',
                kind: BackgroundTaskKind.completeMissing,
                title: '一键补全缺失',
                description: '补全缺失信息',
                status: BackgroundTaskStatus.running,
                createdAt: DateTime.now(),
              ),
            ])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: AppShell(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final pillFinder = find.byKey(const ValueKey('global-task-pill'));
    expect(pillFinder, findsOneWidget);
    expect(find.text('1 个后台任务运行中'), findsOneWidget);

    await tester.tap(pillFinder);
    await tester.pump();

    expect(container.read(currentPageProvider), AppPageIndex.backgroundTasks);
  });
}

class _FakeBackgroundTaskNotifier extends BackgroundTaskNotifier {
  _FakeBackgroundTaskNotifier(this._initial);

  final List<BackgroundTask> _initial;

  @override
  List<BackgroundTask> build() => _initial;
}
