import 'package:asmr_downloader/services/library/library_providers.dart';
import 'package:asmr_downloader/services/library/work_library_status.dart';
import 'package:asmr_downloader/services/organize/organize_providers.dart';
import 'package:asmr_downloader/services/organize/works_index.dart';
import 'package:asmr_downloader/services/ui/ui_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 作品元数据手动编辑对话框（整理前微调）。
///
/// 修改注册表中的标题 / CV / 社团 / 发行日期 / 标签，保存时经
/// [WorksIndex.updateMetadata] 落库并标记手动编辑时间；之后整理
/// （单条/批量）以手动值为准，不被在线 workInfo 覆盖。
///
/// sourceId 只读展示，不可修改（避免破坏目录/路径映射）。
class WorkEditDialog extends ConsumerStatefulWidget {
  const WorkEditDialog({super.key, required this.sourceId});

  final String sourceId;

  @override
  ConsumerState<WorkEditDialog> createState() => _WorkEditDialogState();
}

class _WorkEditDialogState extends ConsumerState<WorkEditDialog> {
  final _titleCtrl = TextEditingController();
  final _cvCtrl = TextEditingController();
  final _circleCtrl = TextEditingController();
  final _releaseCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();

  WorkEntry? _entry;
  bool _loading = true;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _cvCtrl.dispose();
    _circleCtrl.dispose();
    _releaseCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final entry = await ref.read(worksIndexProvider).get(widget.sourceId);
      if (!mounted) return;
      if (entry == null) {
        setState(() {
          _loading = false;
          _error = '注册表中不存在该条目';
        });
        return;
      }
      _titleCtrl.text = entry.title;
      _cvCtrl.text = entry.cvNames;
      _circleCtrl.text = entry.circleName;
      _releaseCtrl.text = entry.releaseDate;
      _tagsCtrl.text = entry.tags.join(', ');
      setState(() {
        _entry = entry;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取元数据失败：$e';
      });
    }
  }

  /// 标签输入：逗号（中英文）/ 顿号 / 空白分隔，空段过滤。
  static List<String> parseTags(String raw) => raw
      .split(RegExp(r'[,，、\s]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  Future<void> _save() async {
    final entry = _entry;
    if (entry == null || _saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(worksIndexProvider).updateMetadata(WorkEntry(
            sourceId: entry.sourceId,
            dlPath: entry.dlPath,
            dirName: entry.dirName,
            title: _titleCtrl.text.trim(),
            cvNames: _cvCtrl.text.trim(),
            circleName: _circleCtrl.text.trim(),
            releaseDate: _releaseCtrl.text.trim(),
            tags: parseTags(_tagsCtrl.text),
            coverUrl: entry.coverUrl,
            organizedAt: entry.organizedAt,
          ));
      if (!mounted) return;
      ref
        ..invalidate(worksLibraryProvider)
        ..invalidate(unorganizedCountProvider)
        ..invalidate(workLibraryStatusProvider);
      showAppSnackBar(context, '已保存元数据：今后整理以手动值为准');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, '保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('编辑作品元数据'),
      content: SizedBox(
        width: 440,
        child: _buildContent(scheme),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _entry == null || _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }

  Widget _buildContent(ColorScheme scheme) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_entry == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          _error ?? '加载失败',
          style: TextStyle(color: scheme.error),
        ),
      );
    }

    InputDecoration fieldDecoration(String label) => InputDecoration(
          labelText: label,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'sourceId：${widget.sourceId}（不可修改）',
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _titleCtrl,
          decoration: fieldDecoration('标题'),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _cvCtrl,
          decoration: fieldDecoration('CV 名单（& 分隔，如 CV1&CV2）'),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _circleCtrl,
          decoration: fieldDecoration('社团名'),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _releaseCtrl,
          decoration: fieldDecoration('发行日期'),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _tagsCtrl,
          decoration: fieldDecoration('标签（逗号/空格分隔）'),
        ),
        const SizedBox(height: 8),
        Text(
          '保存后整理本作品时将优先使用手动值（不会被在线元数据覆盖）。',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5),
        ),
      ],
    );
  }
}