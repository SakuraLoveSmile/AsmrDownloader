import 'package:asmr_downloader/common/config_providers.dart';
import 'package:asmr_downloader/services/ui/ui_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ChickenRice（AI 字幕翻译）配置：exe 路径 + 设备 + 任务 + 自动翻译开关。
class ChickenRiceConfigControls extends ConsumerWidget {
  const ChickenRiceConfigControls({super.key});

  static const List<String> _devices = ['auto', 'cuda', 'cpu'];
  static const List<String> _tasks = ['translate', 'transcribe'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exePath = ref.watch(chickenRiceExePathProvider);
    final device = ref.watch(chickenRiceDeviceProvider);
    final task = ref.watch(chickenRiceTaskProvider);
    final auto = ref.watch(autoTranscribeProvider);
    final ui = ref.read(uiServiceProvider);

    return Tooltip(
      message: 'AI 字幕翻译（Faster-Whisper-ChickenRice）。需自行下载其 release，'
          '并在此选择 infer.exe。translate=翻译成中文，transcribe=原文转录。'
          '已存在同名字幕的音轨会自动跳过',
      child: Padding(
        padding: const EdgeInsets.only(left: 20.0),
        child: Row(
          children: [
            const Text('AI字幕'),
            DropdownButton<String>(
              value: task,
              focusColor: Colors.transparent,
              items: _tasks
                  .map((v) => DropdownMenuItem<String>(
                      value: v, child: Text(_taskLabel(v))))
                  .toList(),
              onChanged: (v) {
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
              onChanged: (v) {
                if (v != null) ui.setChickenRiceDevice(v);
              },
            ),
            const SizedBox(width: 4),
            // exe 路径:图标选择
            IconButton(
              onPressed: ui.pickChickenRiceExe,
              icon: Icon(Icons.code, color: exePath.isEmpty ? Colors.white24 : Colors.white70),
            ),
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
