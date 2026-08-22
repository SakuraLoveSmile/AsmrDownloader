import 'package:asmr_downloader/pages/background_tasks/background_tasks.dart';
import 'package:asmr_downloader/services/tasks/background_task_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SeededTaskNotifier extends BackgroundTaskNotifier {
  _SeededTaskNotifier(this.initialTasks);

  final List<BackgroundTask> initialTasks;

  @override
  List<BackgroundTask> build() => initialTasks;
}

void main() {
  testWidgets('后台任务中心显示运行中的任务和取消入口', (tester) async {
    final task = BackgroundTask(
      id: 'task-1',
      kind: BackgroundTaskKind.completeMissing,
      title: '补全媒体库缺失',
      description: '补全已缓存作品缺少的 tracks 和封面',
      createdAt: DateTime(2026, 8, 21),
      status: BackgroundTaskStatus.running,
      processed: 2,
      total: 5,
      success: 2,
      currentSourceId: 'RJ00001',
      detail: 'tracks 1 · 封面 1',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backgroundTaskProvider.overrideWith(
            () => _SeededTaskNotifier([task]),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: BackgroundTasksPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('后台任务'), findsOneWidget);
    expect(find.text('补全媒体库缺失'), findsOneWidget);
    expect(find.text('运行中'), findsOneWidget);
    expect(find.text('当前：RJ00001'), findsOneWidget);
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('没有任务时显示空状态', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backgroundTaskProvider.overrideWith(
            () => _SeededTaskNotifier(const []),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: BackgroundTasksPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无后台任务'), findsOneWidget);
    expect(find.text('媒体库的批量缓存和一键补全操作会显示在这里。'), findsOneWidget);
  });
}
