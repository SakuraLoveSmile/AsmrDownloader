import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/pages/library/work_list.dart';
import 'package:asmr_downloader/services/library/works_library_service.dart';
import 'package:asmr_downloader/services/organize/navidrome_organizer.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/organize_service.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 构造作品行展示项
WorksListItem mkItem({
  required String sourceId,
  String? verifyNote,
  bool verifyRepairable = false,
}) {
  return WorksListItem(
    sourceId: sourceId,
    title: '标题$sourceId',
    cvNames: 'CV1&CV2',
    circleName: '社团',
    dirName: '社团-标题$sourceId',
    dlPath: '/tmp/dl',
    sourceDir: p.join('/tmp/dl', '社团-标题$sourceId', sourceId),
    sourceDirOverride: '',
    organizedAt: '2026-01-01T00:00:00.000',
    verifyNote: verifyNote,
    verifyRepairable: verifyRepairable,
    trackCount: 1,
    missingSubtitleCount: 0,
    convertibleVttCount: 0,
  );
}

/// 清空缺陷字段（模拟修复成功并复验通过）
WorksListItem cleared(WorksListItem w) => mkItem(
      sourceId: w.sourceId,
      verifyNote: null,
      verifyRepairable: false,
    );

/// 修复成功的伪造整理服务：把 itemsState 中对应作品的缺陷清空，
/// 并返回「校验通过」的 outcome。
class FakeRepairOrganizeService extends OrganizeService {
  final StateProvider<List<WorksListItem>> itemsState;
  FakeRepairOrganizeService(super.ref, this.itemsState);

  @override
  Future<OrganizeEntryOutcome> organizeEntry(
    WorkEntry entry, {
    required String targetRoot,
    bool fetchWorkInfo = true,
    bool keepDirStructure = false,
    bool forceWavRewrite = false,
    bool forceReorganize = false,
  }) async {
    final current = ref.read(itemsState);
    ref.read(itemsState.notifier).state =
        current.map((w) => w.sourceId == entry.sourceId ? cleared(w) : w).toList();
    return OrganizeEntryOutcome(
      result: const OrganizeResult(copied: 1, skipped: 0, targetDir: ''),
      resolvedEntry: entry.copyWith(verifyNote: null, verifyRepairable: false),
      verifyNote: '校验通过',
    );
  }
}

/// 用 itemsState 持有作品列表、渲染首个作品行的测试外壳。
/// 修复按钮回调调用伪造 organizeEntry，后者会更新 itemsState 触发重建。
class _RowHarness extends ConsumerStatefulWidget {
  const _RowHarness({required this.itemsState});
  final StateProvider<List<WorksListItem>> itemsState;

  @override
  ConsumerState<_RowHarness> createState() => _RowHarnessState();
}

class _RowHarnessState extends ConsumerState<_RowHarness> {
  @override
  Widget build(BuildContext context) {
    final items = ref.watch(widget.itemsState);
    final item = items.first;
    return MaterialApp(
      home: Scaffold(
        body: WorkRow(
          key: ValueKey(item.sourceId),
          item: item,
          selected: false,
          transcribing: false,
          deleteEnabled: true,
          onToggleSelect: () {},
          onDelete: () {},
          onRepair: () async {
            await ref.read(organizeServiceProvider).organizeEntry(
                  WorkEntry(
                    sourceId: item.sourceId,
                    dlPath: item.dlPath,
                    dirName: item.dirName,
                    title: item.title,
                    cvNames: item.cvNames,
                    circleName: item.circleName,
                    organizedAt: item.organizedAt,
                  ),
                  targetRoot: ref.read(navidromePathProvider),
                  fetchWorkInfo: false,
                );
          },
        ),
      ),
    );
  }
}

void main() {
  /// 构造容器与对应的 itemsState（二者共享同一 itemsState 实例）。
  /// 注意：本测试不触碰真实 WorksIndex/数据库（drift 在 testWidgets 区下会死锁），
  /// 展示与修复逻辑通过 itemsState + 伪造 organizeServiceProvider 驱动。
  (ProviderContainer, StateProvider<List<WorksListItem>>) makeContainer(
    List<WorksListItem> items,
  ) {
    final itemsState = StateProvider<List<WorksListItem>>((ref) => items);
    final container = ProviderContainer(overrides: [
      itemsState,
      navidromePathProvider.overrideWith((ref) => '/tmp/nav'),
      organizeServiceProvider.overrideWith(
          (ref) => FakeRepairOrganizeService(ref, itemsState)),
    ]);
    addTearDown(container.dispose);
    return (container, itemsState);
  }

  /// 显式推进若干帧（避免 pumpAndSettle 在本环境下挂起）。
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  Widget buildRow(ProviderContainer container, WorksListItem item) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: WorkRow(
            item: item,
            selected: false,
            transcribing: false,
            deleteEnabled: true,
            onToggleSelect: () {},
            onDelete: () {},
            onRepair: () {},
          ),
        ),
      ),
    );
  }

  Widget buildHarness(
      ProviderContainer container,
      StateProvider<List<WorksListItem>> itemsState) {
    return UncontrolledProviderScope(
      container: container,
      child: _RowHarness(itemsState: itemsState),
    );
  }

  testWidgets('缺陷作品显示警告图标，Tooltip 显示缺陷摘要', (tester) async {
    final item = mkItem(sourceId: 'RJ00001', verifyNote: '2 首缺内嵌歌词');
    final (container, _) = makeContainer([item]);

    await tester.pumpWidget(buildRow(container, item));
    await settle(tester);

    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    final tooltip = tester.widget<Tooltip>(
      find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == '2 首缺内嵌歌词'),
    );
    expect(tooltip.message, '2 首缺内嵌歌词');
  });

  testWidgets('可修复缺陷显示修复按钮', (tester) async {
    final item = mkItem(
        sourceId: 'RJ00001',
        verifyNote: '2 首缺内嵌歌词',
        verifyRepairable: true);
    final (container, _) = makeContainer([item]);

    await tester.pumpWidget(buildRow(container, item));
    await settle(tester);

    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.byIcon(Icons.build_rounded), findsOneWidget);
  });

  testWidgets('不可修复缺陷不显示修复按钮', (tester) async {
    final item = mkItem(
        sourceId: 'RJ00001',
        verifyNote: '1 个 wav 第三方标签，无法重写',
        verifyRepairable: false);
    final (container, _) = makeContainer([item]);

    await tester.pumpWidget(buildRow(container, item));
    await settle(tester);

    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.byIcon(Icons.build_rounded), findsNothing);
  });

  testWidgets('修复成功并复验通过后警告消失', (tester) async {
    final items = [
      mkItem(
          sourceId: 'RJ00001',
          verifyNote: '2 首缺内嵌歌词',
          verifyRepairable: true),
    ];
    final (container, itemsState) = makeContainer(items);

    await tester.pumpWidget(buildHarness(container, itemsState));
    await settle(tester);

    // 修复前：警告 + 修复按钮都在
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.byIcon(Icons.build_rounded), findsOneWidget);

    // 点击修复（伪造 organizeEntry 会清空缺陷并复验通过）
    await tester.tap(find.byIcon(Icons.build_rounded));
    await settle(tester);

    // 修复后：缺陷清除，警告图标消失；修复按钮也随之消失
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    expect(find.byIcon(Icons.build_rounded), findsNothing);
  });
}
