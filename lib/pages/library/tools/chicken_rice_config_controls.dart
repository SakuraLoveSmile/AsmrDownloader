import 'dart:io';

import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/pages/components/labeled_checkbox.dart';
import 'package:asmr_downloader/pages/library/tools/engine_setup_dialog.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// ChickenRice（AI 字幕翻译）配置：脚本选择 + 设备 + 任务 + 自动翻译开关。
///
/// 脚本可选手动下载的 ChickenRice 的 `.bat`（如 `运行(翻译)(GPU).bat`）
/// 或 `infer.exe`：
/// - 选 .bat：翻译/转录与设备由所选 bat 决定，任务/设备下拉禁用；
/// - 选 .exe：任务/设备下拉生效，参数由本控件拼接。
///
/// **平台限制**：ChickenRice 官方仅提供 Windows 的 exe/bat，macOS 不支持
/// 翻译功能 —— 非 Windows 平台整体禁用（置灰 + 拦截所有交互）。
class ChickenRiceConfigControls extends ConsumerWidget {
  const ChickenRiceConfigControls({super.key});

  static const List<String> _devices = ['auto', 'cuda', 'cpu'];
  static const List<String> _tasks = ['translate', 'transcribe'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scriptPath = ref.watch(chickenRiceScriptPathProvider);
    final device = ref.watch(chickenRiceDeviceProvider);
    final task = ref.watch(chickenRiceTaskProvider);
    final auto = ref.watch(autoTranscribeProvider);
    final isBat = scriptPath.toLowerCase().endsWith('.bat') ||
        scriptPath.toLowerCase().endsWith('.cmd');
    // macOS 不支持翻译功能：非 Windows 整体禁用
    final supported = Platform.isWindows;
    final ui = ref.read(uiServiceProvider);

    return Tooltip(
      message: supported
          ? 'AI 字幕翻译（Faster-Whisper-ChickenRice）。选择其 release 中的 '
              '.bat 启动脚本（如 运行(翻译)(GPU).bat，翻译/转录与设备由所选 bat 决定）'
              '或 infer.exe（此时用下拉选择任务/设备）。'
              '已存在同名字幕的音轨会自动跳过'
          : 'AI 字幕翻译仅支持 Windows（当前平台不支持）',
      child: Opacity(
        opacity: supported ? 1.0 : 0.45,
        child: Row(
          children: [
            Text('AI字幕',
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.8))),
            const SizedBox(width: 6),
            // 任务/设备：bat 模式下由 bat 决定，禁用
            DropdownMenu<String>(
              initialSelection: task,
              enabled: !isBat && supported,
              dropdownMenuEntries: _tasks
                  .map((v) =>
                      DropdownMenuEntry<String>(value: v, label: _taskLabel(v)))
                  .toList(),
              onSelected: (v) {
                if (v != null) ui.setChickenRiceTask(v);
              },
            ),
            const SizedBox(width: 4),
            DropdownMenu<String>(
              initialSelection: device,
              enabled: !isBat && supported,
              dropdownMenuEntries: _devices
                  .map((v) => DropdownMenuEntry<String>(value: v, label: v))
                  .toList(),
              onSelected: (v) {
                if (v != null) ui.setChickenRiceDevice(v);
              },
            ),
            const SizedBox(width: 4),
            // 脚本选择：显示文件名，悬停可见完整路径
            Tooltip(
              message: scriptPath.isEmpty
                  ? '选择 ChickenRice 的 .bat 启动脚本或 infer.exe'
                  : scriptPath,
              child: OutlinedButton.icon(
                onPressed: supported ? ui.pickChickenRiceScript : null,
                icon: const Icon(Icons.terminal, size: 14),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    scriptPath.isEmpty ? '选择脚本' : p.basename(scriptPath),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // 内置安装器：自动下载 ChickenRice 运行时 + 模型，免手动配置
            Tooltip(
              message: '一键安装 AI 翻译引擎（自动下载运行时与模型，'
                  '装完自动配置，无需手动选择脚本）',
              child: OutlinedButton.icon(
                onPressed:
                    supported ? () => showEngineSetupDialog(context) : null,
                icon: const Icon(Icons.download, size: 14),
                label: const Text('安装引擎', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            // 自动翻译开关
            LabeledCheckbox(
              label: '自动',
              value: auto,
              onChanged: supported ? ui.onAutoTranscribeChanged : null,
            ),
          ],
        ),
      ),
    );
  }

  static String _taskLabel(String task) {
    return task == 'translate' ? '翻译' : '转录';
  }
}
