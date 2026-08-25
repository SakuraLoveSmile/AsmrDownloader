import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/engine/chicken_rice_engine_service.dart';
import 'package:asmr_downloader/services/engine/engine_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:asmr_downloader/ui/app_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 弹出 AI 翻译引擎安装向导。
Future<void> showEngineSetupDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const EngineSetupDialog(),
  );
}

/// AI 翻译引擎（ChickenRice）内置安装向导：
/// 选变体（NVIDIA/AMD）与任务 → 自选安装目录 → 自动下载/校验/解压/模型。
///
/// 上游产物为 MIT（Copyright (c) 2025 TransWithAI），应用内按需下载，
/// 不随本应用分发（见 THIRD-PARTY.md）。
class EngineSetupDialog extends ConsumerStatefulWidget {
  const EngineSetupDialog({super.key});

  @override
  ConsumerState<EngineSetupDialog> createState() => _EngineSetupDialogState();
}

class _EngineSetupDialogState extends ConsumerState<EngineSetupDialog> {
  String _variant = 'cu128';
  String _task = 'translate';
  String _installDir = '';
  EngineProbeResult? _probe;
  bool _probing = false;

  /// 已点击「取消安装」、等待取消生效（解压等阶段需几秒才中断）
  bool _canceling = false;

  @override
  void initState() {
    super.initState();
    _installDir = ref.read(chickenRiceEngineInstallDirProvider);
    final savedVariant = ref.read(chickenRiceEngineVariantProvider);
    if (EngineVariant.all.any((v) => v.id == savedVariant)) {
      _variant = savedVariant;
    }
    _task = ref.read(chickenRiceTaskProvider);
    _refreshProbe();
  }

  Future<void> _refreshProbe([String? dir]) async {
    setState(() => _probing = true);
    // 支持探测任意候选目录（新选的安装目录也能即时检测已有引擎）
    final result = await ref
        .read(chickenRiceEngineServiceProvider)
        .probe(dir ?? ref.read(chickenRiceEngineInstallDirProvider));
    if (mounted) {
      setState(() {
        _probe = result;
        _probing = false;
      });
    }
  }

  Future<void> _pickDir() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || !mounted) return;
    setState(() => _installDir = dir);
    // 选完立即探测：目录里已有完整引擎时可直接一键启用，无需重装
    await _refreshProbe(dir);
  }

  Future<void> _startInstall() async {
    if (_installDir.isEmpty) return;
    setState(() => _canceling = false);
    final ui = ref.read(uiServiceProvider);
    await ui.installEngine(
      installDir: _installDir,
      variant: _variant,
      task: _task,
    );
    // 状态由 engineInstallStateProvider 驱动；完成后刷新探测
    if (mounted) await _refreshProbe();
  }

  void _requestCancelInstall() {
    if (_canceling) return;
    setState(() => _canceling = true);
    ref.read(uiServiceProvider).cancelEngineInstall();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(engineInstallStateProvider);
    final busy = state.busy;
    final ui = ref.read(uiServiceProvider);
    // 探测到完整引擎但当前配置未指向它 → 可一键启用（无需重装）
    final scriptPath = ref.watch(chickenRiceScriptPathProvider);
    final probe = _probe;
    final canLinkExisting = !busy &&
        probe != null &&
        probe.installed &&
        probe.modelsReady &&
        probe.exePath != scriptPath;

    return AlertDialog(
      title: const Text('AI 翻译引擎（内置安装）'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '自动下载 ChickenRice 运行时（MIT 开源，约 3.3 GB）与 '
              'Whisper 模型（约 3.1 GB），装到所选目录后自动配置，'
              '无需手动下载和选择脚本。已下载部分支持断点续传。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            _statusBanner(theme),
            const SizedBox(height: 12),
            if (busy)
              _progressView(theme, state)
            else ...[
              Row(
                children: [
                  Expanded(
                    child: DropdownMenu<String>(
                      initialSelection: _variant,
                      label: const Text('显卡变体'),
                      dropdownMenuEntries: [
                        for (final v in EngineVariant.all)
                          DropdownMenuEntry<String>(
                            value: v.id,
                            label: '${v.label}（${v.description}）',
                          ),
                      ],
                      onSelected: (v) {
                        if (v != null) setState(() => _variant = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownMenu<String>(
                    initialSelection: _task,
                    label: const Text('任务'),
                    dropdownMenuEntries: const [
                      DropdownMenuEntry(value: 'translate', label: '翻译（日→中）'),
                      DropdownMenuEntry(value: 'transcribe', label: '转录（日文原文）'),
                    ],
                    onSelected: (v) {
                      if (v != null) setState(() => _task = v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: TextEditingController(text: _installDir),
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: '安装目录',
                        hintText: '选择剩余空间 ≥ 12 GB 的目录',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _pickDir,
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: const Text('选择'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '无纯 CPU 发行包；CPU 用户请在「AI字幕」处手动选择外部脚本。'
                'AMD 变体需安装对应 ROCm 驱动。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (!busy && state.phase == EnginePhase.failed) ...[
              const SizedBox(height: 8),
              Text(state.error ?? '安装失败',
                  style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (!busy && state.phase == EnginePhase.canceled) ...[
              const SizedBox(height: 8),
              Text(state.error ?? '已取消', style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(busy ? '后台继续' : '关闭'),
        ),
        if (busy)
          TextButton(
            onPressed: _canceling ? null : _requestCancelInstall,
            child: Text(_canceling ? '正在取消…' : '取消安装'),
          )
        else ...[
          if (canLinkExisting)
            FilledButton.tonal(
              onPressed: () async {
                final exe =
                    await ui.linkInstalledEngine(installDir: _installDir);
                if (exe != null && context.mounted) {
                  Navigator.of(context).pop();
                } else if (context.mounted) {
                  ref.read(uiServiceProvider).showSnack(
                      context: context, '引擎不完整（缺少 exe 或模型），无法启用，请先安装');
                }
              },
              child: const Text('使用已安装的引擎'),
            ),
          FilledButton(
            onPressed: _installDir.isEmpty ? null : _startInstall,
            child: Text(_probe?.installed == true ? '重新安装 / 补下模型' : '开始安装'),
          ),
        ],
      ],
    );
  }

  Widget _statusBanner(ThemeData theme) {
    final probe = _probe;
    if (_probing) {
      return const Row(
        children: [
          SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('正在检测已安装的引擎…'),
        ],
      );
    }
    if (probe == null || !probe.installed) {
      return Text('状态：未安装', style: theme.textTheme.bodyMedium);
    }
    final modelOk = probe.modelsReady;
    return Row(
      children: [
        Icon(
          modelOk ? Icons.check_circle : Icons.warning_amber,
          size: 16,
          color: modelOk ? AppColors.success : AppColors.warning,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            modelOk
                ? '状态：已安装，模型完整（${probe.exePath}）'
                : '状态：已安装，模型缺失（重新安装可补下，已存在文件自动跳过）',
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        IconButton(
          onPressed: _refreshProbe,
          icon: const Icon(Icons.refresh, size: 16),
          tooltip: '重新校验',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _progressView(ThemeData theme, EngineInstallState state) {
    final stepInfo =
        state.stepCount > 0 ? '（${state.stepIndex}/${state.stepCount}）' : '';
    final bytesInfo = state.total > 0
        ? ' · ${_fmtSize(state.received)} / ${_fmtSize(state.total)}'
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${state.message}$stepInfo$bytesInfo',
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: state.total > 0 ? state.fraction : null),
        const SizedBox(height: 8),
        Text(
          '关闭窗口不中断安装，可随时重新打开查看进度。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  static String _fmtSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '$bytes B';
  }
}
