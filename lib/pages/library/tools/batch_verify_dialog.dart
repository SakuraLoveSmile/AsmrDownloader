import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/library/library_providers.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/verify_service.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:asmr_downloader/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 批量校验对话框：
/// - 开始前：说明 + 待校验作品数（注册表中 organizedAt 非空的条目）
/// - 运行中：进度条 + 当前 sourceId + 取消（当前作品完成后停止）
/// - 完成：汇总 + 每作品结果行；存在可修复项时显示「修复缺失（N）」按钮，
///   对缺陷作品重新整理（wav 强制重写），完成后自动重新校验刷新结果。
class BatchVerifyDialog extends ConsumerStatefulWidget {
  const BatchVerifyDialog({super.key});

  @override
  ConsumerState<BatchVerifyDialog> createState() => _BatchVerifyDialogState();
}

class _BatchVerifyDialogState extends ConsumerState<BatchVerifyDialog> {
  bool _running = false;
  bool _repairing = false;
  bool _cancelled = false;
  String? _error;
  int _total = 0;
  int _done = 0;
  int _repairTotal = 0;
  int _repairDone = 0;
  String _currentSourceId = '';
  List<VerifyWorkResult>? _results;

  @override
  void initState() {
    super.initState();
    ref.read(worksIndexProvider).list().then((entries) {
      if (mounted) {
        setState(() {
          _total = entries.where((e) => e.organizedAt != null).length;
        });
      }
    });
  }

  @override
  void dispose() {
    _cancelled = true; // 对话框关闭时停止校验/修复（当前作品完成后）
    super.dispose();
  }

  Future<String?> _ensureTargetRoot() async {
    var targetRoot = ref.read(navidromePathProvider);
    if (targetRoot.isEmpty) {
      await ref.read(uiServiceProvider).pickNavidromePath();
      targetRoot = ref.read(navidromePathProvider);
      if (targetRoot.isEmpty) {
        setState(() => _error = '请先设置 Navidrome 整理路径');
        return null;
      }
    }
    return targetRoot;
  }

  Future<List<WorkEntry>> _organizedEntries() async {
    final entries = await ref.read(worksIndexProvider).list();
    return entries.where((e) => e.organizedAt != null).toList();
  }

  Future<void> _start() async {
    final targetRoot = await _ensureTargetRoot();
    if (targetRoot == null) return;

    setState(() {
      _running = true;
      _repairing = false;
      _cancelled = false;
      _error = null;
      _done = 0;
      _currentSourceId = '';
      _results = null;
    });

    final entries = await _organizedEntries();
    final results = await _verifyAll(targetRoot, entries);
    if (mounted) {
      setState(() {
        _running = false;
        _results = results;
        _done = results.length; // 取消时只显示已完成部分
        _currentSourceId = '';
      });
    }
  }

  /// 串行校验一批作品；取消时返回已完成部分。
  Future<List<VerifyWorkResult>> _verifyAll(
      String targetRoot, List<WorkEntry> entries) async {
    final results = <VerifyWorkResult>[];
    for (var i = 0; i < entries.length; i++) {
      if (_cancelled) break;
      final entry = entries[i];
      if (mounted) {
        setState(() {
          _done = i;
          _currentSourceId = entry.sourceId;
        });
      }
      try {
        results.add(await ref.read(verifyServiceProvider).verifyWork(
              entry,
              targetRoot: targetRoot,
              keepDirStructure: ref.read(keepOrganizeDirStructureProvider),
            ));
      } catch (e) {
        results.add(VerifyWorkResult(
          sourceId: entry.sourceId,
          targetFound: false,
          checkedAudio: 0,
          missingLyrics: 0,
          missingCover: 0,
          readErrors: 0,
          coverJpgMissing: false,
          hasLyricsSource: false,
          hasCoverSource: false,
          skippedThirdParty: 0,
          problems: ['校验失败：$e'],
        ));
      }
    }
    return results;
  }

  /// 对可修复的缺陷作品重新整理（wav 强制重写），完成后自动重新校验。
  Future<void> _repair() async {
    final defects = (_results ?? const []).where((r) => r.repairable).toList();
    if (defects.isEmpty) return;
    final targetRoot = ref.read(navidromePathProvider);

    setState(() {
      _repairing = true;
      _cancelled = false;
      _repairTotal = defects.length;
      _repairDone = 0;
    });

    final organizer = ref.read(organizeServiceProvider);
    final index = ref.read(worksIndexProvider);
    for (final defect in defects) {
      if (_cancelled) break;
      final entry = await index.get(defect.sourceId);
      if (entry == null) continue;
      if (mounted) {
        setState(() {
          _currentSourceId = entry.sourceId;
          _done = 0;
        });
      }
      try {
        final outcome = await organizer.organizeEntry(
          entry,
          targetRoot: targetRoot,
          // 重拉封面/元数据，保证与目录解析一致；wav 强制剥离旧标签重写
          fetchWorkInfo: true,
          keepDirStructure: ref.read(keepOrganizeDirStructureProvider),
          forceWavRewrite: true,
        );
        if (outcome.result != null && mounted) {
          await index.upsert(outcome.resolvedEntry
              .copyWith(organizedAt: DateTime.now().toIso8601String()));
          setState(() => _repairDone++);
        }
      } catch (e) {
        // 单个作品修复失败不阻断其余作品
      }
    }

    // 修复完成后自动重新校验，刷新结果；
    // 取消后也重新校验已完成的部分，保证展示与磁盘一致
    _cancelled = false;
    final entries = await _organizedEntries();
    final results = await _verifyAll(targetRoot, entries);
    if (mounted) {
      setState(() {
        _repairing = false;
        _results = results;
        _done = results.length;
        _currentSourceId = '';
      });
    }
    ref.invalidate(worksLibraryProvider);
    ref.invalidate(unorganizedCountProvider);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('校验整理产物'),
      content: SizedBox(width: 480, child: _buildContent(context)),
      actions: _buildActions(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_running || _repairing) return _buildRunning();
    if (_results != null) return _buildDone(context);
    return _buildIdle(context);
  }

  /// 开始前的说明界面
  Widget _buildIdle(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            '逐作品检查整理产物：内嵌歌词（mp3→USLT / flac→LYRICS / '
            'wav→id3 USLT）与封面（APIC/PICTURE）。只读检查，不修改任何文件。',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Text(
            '缺歌词/封面的作品可点击「修复缺失」重新整理补齐'
            '（重新拉取封面、重写全部音频标签）。',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Text('待校验作品：$_total（注册表中已整理过的条目）',
            style: Theme.of(context).textTheme.bodyMedium),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    );
  }

  /// 运行中（校验/修复）的进度界面
  Widget _buildRunning() {
    final total = _repairing ? _repairTotal : _total;
    final done = _repairing ? _repairDone : _done;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (total > 0) LinearProgressIndicator(value: done / total),
        const SizedBox(height: 8),
        Text('进度：$done / $total', style: Theme.of(context).textTheme.bodySmall),
        if (_currentSourceId.isNotEmpty)
          Text('当前：$_currentSourceId',
              style: Theme.of(context).textTheme.bodyMedium),
        Text(
          _repairing ? '修复中：重新拉取封面并重写全部音频标签…' : '校验文件中…',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Text('取消（当前作品完成后停止）', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  /// 完成后的汇总界面
  Widget _buildDone(BuildContext context) {
    final results = _results!;
    final pass = results.where((r) => r.ok).length;
    final missingTarget = results.where((r) => !r.targetFound).length;
    final repairable = results.where((r) => r.repairable).length;
    final missingLyrics =
        results.fold<int>(0, (sum, r) => sum + r.missingLyrics);
    final missingCover = results.fold<int>(0, (sum, r) => sum + r.missingCover);
    final readErrors = results.fold<int>(0, (sum, r) => sum + r.readErrors);
    final thirdParty =
        results.fold<int>(0, (sum, r) => sum + r.skippedThirdParty);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '完成：通过 $pass，缺歌词 $missingLyrics，缺封面 $missingCover，'
          '产物缺失 $missingTarget',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (readErrors > 0 || thirdParty > 0) ...[
          const SizedBox(height: 4),
          Text('读取失败 $readErrors；第三方标签不可重写 $thirdParty（详见各行）',
              style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 8),
        if (repairable > 0 && !_repairing)
          Text('可点击「修复缺失（$repairable）」重新整理补齐（wav 强制重写）。',
              style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Flexible(child: _buildResultList(results)),
      ],
    );
  }

  Widget _buildResultList(List<VerifyWorkResult> results) {
    if (results.isEmpty) return const Text('没有已整理的作品');
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: results.length,
        itemBuilder: (context, i) {
          final item = results[i];
          final icon = !item.targetFound
              ? const Icon(Icons.folder_off,
                  size: 16, color: AppColors.textFile)
              : item.ok
                  ? const Icon(Icons.check_circle,
                      size: 16, color: AppColors.success)
                  : const Icon(Icons.warning_amber_rounded,
                      size: 16, color: AppColors.warning);
          return ListTile(
            dense: true,
            leading: icon,
            title: Text(item.sourceId,
                style: Theme.of(context).textTheme.bodySmall),
            subtitle: Text(
              item.ok ? '校验通过' : item.problems.join('；'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    if (_running || _repairing) {
      return [
        TextButton(
          onPressed: () => setState(() => _cancelled = true),
          child: const Text('取消（当前作品完成后停止）'),
        ),
      ];
    }
    if (_results != null) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        if (_results!.any((r) => r.repairable))
          FilledButton(
            onPressed: _repair,
            child: Text('修复缺失（${_results!.where((r) => r.repairable).length}）'),
          ),
      ];
    }
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('关闭'),
      ),
      FilledButton(
        onPressed: _total == 0 ? null : _start,
        child: const Text('开始校验'),
      ),
    ];
  }
}
