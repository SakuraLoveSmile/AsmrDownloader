import 'package:asmr_downloader/common/config_providers.dart';
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
    final ui = ref.read(uiServiceProvider);

    return Tooltip(
      message: 'AI 字幕翻译（Faster-Whisper-ChickenRice）。选择其 release 中的 '
          '.bat 启动脚本（如 运行(翻译)(GPU).bat，翻译/转录与设备由所选 bat 决定）'
          '或 infer.exe（此时用下拉选择任务/设备）。'
          '已存在同名字幕的音轨会自动跳过',
      child: Padding(
        padding: const EdgeInsets.only(left: 20.0),
        child: Row(
          children: [
            const Text('AI字幕'),
            // 任务/设备：bat 模式下由 bat 决定，禁用
            DropdownButton<String>(
              value: task,
              focusColor: Colors.transparent,
              items: _tasks
                  .map((v) => DropdownMenuItem<String>(
                      value: v, child: Text(_taskLabel(v))))
                  .toList(),
              onChanged: isBat
                  ? null
                  : (v) {
                      if (v != null) ui.setChickenRiceTask(v);
                    },
            ),
            const SizedBox(width: 4),
            DropdownButton<String>(
              value: device,
              focusColor: Colors.transparent,
              items: _devices
                  .map((v) => DropdownMenuItem<String>(
                      value: v, child: Text(v)))
                  .toList(),
              onChanged: isBat
                  ? null
                  : (v) {
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
                onPressed: ui.pickChickenRiceScript,
                icon: Icon(Icons.terminal,
                    size: 14,
                    color: scriptPath.isEmpty
                        ? Colors.white38
                        : Colors.white70),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    scriptPath.isEmpty ? '选择脚本' : p.basename(scriptPath),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: scriptPath.isEmpty
                          ? Colors.white24
                          : Colors.white38),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  foregroundColor: Colors.white70,
                ),
              ),
            ),
            const SizedBox(width: 4),
            // 自动翻译开关
            const Text('自动'),
            Checkbox(
              value: auto,
              onChanged: ui.onAutoTranscribeChanged,
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
