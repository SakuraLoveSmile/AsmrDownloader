# AsmrDownloader × Faster-Whisper-TransWithAI-ChickenRice 联动适配方案

> 状态：调研完成，待确认后实施（本轮不写代码）
> 调研对象：https://github.com/TransWithAI/Faster-Whisper-TransWithAI-ChickenRice

---

## 1. 背景与目标

AsmrDownloader 是 asmr.one 的 GUI 下载工具（Flutter 桌面端，Windows/macOS），下载音声作品后会将 `.vtt` 字幕转为 LRC 并整理进 Navidrome 媒体库。目前字幕来自 asmr.one 官方（多为日文原文）。

[Faster-Whisper-TransWithAI-ChickenRice](https://github.com/TransWithAI/Faster-Whisper-TransWithAI-ChickenRice)（下称 ChickenRice）是专为「音声（ASMR）」优化的本地日文→中文转录/翻译 CLI 工具（Faster-Whisper + 音声优化 VAD）。

**联动的目标**：在 AsmrDownloader 内一键调用 ChickenRice，为下载好的音轨生成本地 AI 中文字幕，并与现有 Navidrome 整理链路无缝衔接。

---

## 2. 关键结论（调研事实）

### 2.1 ChickenRice 是纯 CLI 程序
- 入口：`infer.exe`（PyInstaller 打包）或 `python infer.py`，Windows 上提供 `.bat` 拖放脚本。
- 无 HTTP/RPC 接口，联动只能走**进程调用 + 命令行参数 + 文件系统**。

### 2.2 核心 CLI 参数（联动用到的）
| 参数 | 说明 | 映射 |
|---|---|---|
| `base_dirs...`（位置参数） | 音频文件或文件夹 | 传入作品目录 |
| `--output_dir=<path>` | 输出目录（默认源文件同目录） | 作品目录 |
| `--sub_formats="lrc,vtt,srt"` | 输出字幕格式 | 默认 `lrc`（与整理对齐） |
| `--audio_suffixes="wav,flac,mp3"` | 处理的音频后缀 | 匹配音轨 |
| `--task=translate\|transcribe` | 翻译(中文)/转录(日文) | 默认 `translate` |
| `--device=cuda\|cpu\|auto` | 计算设备 | 用户配置 |
| `--compute_type`, `--model_name_or_path` | 精度 / 模型路径 | 高级配置 |
| `--overwrite` | 覆盖已存在字幕 | 幂等/重跑 |

### 2.3 ChickenRice 的关键行为（对联动有利）
1. **递归扫描**：传入文件夹会 `os.walk` 递归处理其中所有音频。
2. **输出命名**：对 `foo.wav` 在同目录生成 `foo.lrc` / `.vtt` / `.srt` —— **与音轨同名的侧车字幕**。
3. **智能跳过**：`_scan` 中 `if sub_path.exists() and not overwrite: continue` —— 已存在的字幕自动跳过，天然支持增量/断点续翻。
4. **固定模型路径**：VAD 模型硬编码为 `models/whisper_vad.onnx`，主模型默认 `models` 目录；运行时 `os.chdir` 到 exe 所在目录。**因此必须以 exe 所在目录为工作目录启动**，模型才找得到。
5. **进度输出**：VAD/批处理进度写到 stdout（`\r` 刷新 + `progress.vad` 日志行），但**没有结构化进度条**，需要解析日志文本估算进度。

### 2.4 依赖重（本项目不内置）
ChickenRice 官方 release 分「翻译版 / 转录版 / 无主模型版」，并区分 NVIDIA CUDA（11.8/12.2/12.8）、AMD ROCm（gfx 系列）、CPU。模型 + GPU 运行时体积巨大，**AsmrDownloader 不能也不会内置**，需用户自行下载对应 release 并用本应用「定位」其 `infer.exe`。

### 2.5 字幕语言现状
asmr.one 的 `tracks` 接口返回的音轨 `type` 含 `subtitle`（vtt）。现有整理逻辑注释「同名 .lrc 优先（人工字幕）」——即官方字幕可能同时存在 `.lrc`（人工/官方）与 `.vtt`（自动转录，多为日文）。

**用户需求（已确认）**：官方字幕是中文 → 直接用官方；官方字幕不是中文（如日文 vtt）→ 用 ChickenRice 的 AI 中文字幕。

---

## 3. 方案设计

### 3.1 总体架构
```
下载完成
   │
   ├─ 触发 "生成本地 AI 字幕"
   │      └─ ChickenRiceService.run(worksDir, opts)
   │            ├─ 定位 infer.exe / 校验存在 / 环境自检
   │            ├─ Process.start(工作目录=exe目录, 参数拼接)
   │            ├─ 解析 stdout 进度 → Riverpod 状态
   │            └─ 退出码/产物校验 → 完成/失败提示
   │
   └─ Navidrome 整理（现有）
          └─ 字幕选择策略（见 3.4）
```

### 3.2 新增模块
- **配置项**（`lib/common/config_providers.dart` 扩展，持久化到 `asmr_dl_config.json`）：
  - `chickenRiceExePath`：`infer.exe` 绝对路径（或 `.bat`）
  - `chickenRiceDevice`：`auto` / `cuda` / `cpu`
  - `chickenRiceTask`：`translate`（默认）/ `transcribe`
  - `chickenRiceFormats`：默认 `lrc`
  - `autoTranscribeProvider`：下载后自动翻译开关（默认关）
- **服务**（`lib/services/transcribe/chicken_rice_service.dart`）：
  - `Future<bool> probe()`：exe 存在性 + `--help` 自检 + CUDA 探测（复用其内置 `diag`/`--console` 的 `diagnose`，非交互式调用）。
  - `Future<TranscribeResult> run(String dir, {CancelToken})`：参数拼接、启动、进度解析、取消（kill 进程）、退出码/产物判定。
  - 进度状态 Provider：`transcribeStatusProvider`（idle/running/done/failed）+ `transcribeProgressProvider`（当前文件 / 百分比）。
- **UI**（`lib/pages/downloader/config_settings/components/`）：
  - 新增「AI 字幕翻译」分组的路径选择器（仿 `navidrome_path_picker.dart`）与设备/任务下拉。
  - 手动触发按钮「生成 AI 字幕」（仿 `organize_button.dart`），对当前作品立即执行。
  - 进度展示（仿 `download_progress` 组件思路）。

### 3.3 触发时机
1. **自动（用户确认，带开关）**：`download_manager.dart` 的 completed 分支，若 `autoTranscribeProvider` 开启且 exe 已配置，**先按 3.4 规则过滤出「无同名字幕的音轨」**——若无则跳过，否则异步调用 ChickenRice，完成时提示。
2. **手动**：作品下载完成后，点「生成 AI 字幕」按钮对当前 `<voiceWorkPath>/<sourceId>` 执行（同样先过滤）。
3. **批量（可选，二期）**：对已下载未翻译的注册表作品批量执行（复用 `works_index`，逐个过滤）。

### 3.4 字幕策略：按「同名字幕是否存在」判断（用户最终确认）

核心判据极简，**不做语言探测**：

> 对每个音轨，若已存在**同名 `.vtt` 或 `.lrc` 官方字幕**（asmr.one 提供），则跳过 AI 翻译；
> 仅对**没有任何官方字幕的音轨**调用 ChickenRice 生成 AI 中文字幕。

```
遍历作品目录中每个音频音轨
   ├─ 同名 .vtt 或 .lrc 已存在 → 跳过（官方字幕可用，不浪费算力）
   └─ 无同名字幕文件            → 调用 ChickenRice 翻译该音轨
```

**实现要点**：
- 判定纯靠文件系统：`<音轨stem>.vtt` / `<音轨stem>.lrc`（覆盖「带音频扩展名」的 `foo.mp3.vtt` 与不带扩展名的 `foo.vtt` 两种命名，复用整理逻辑中已有的 key 匹配方式）。
- ChickenRice 支持传入**单个文件**作为 `base_dirs`，因此可把「缺官方字幕的音轨列表」逐个（或拼成目录）传入，实现**精确到文件级**的增量翻译，天然不与官方字幕冲突。
- 无语言探测、无 `TranslateNeed` 中间态，代码大幅简化、判定确定性高。

**整理互作用**：
- 有官方字幕的音轨：现有逻辑不变。
- AI 生成的音轨：ChickenRice 输出中文 `.lrc`，整理时嵌入标签；**日文 vtt 不再保留**（用户选择「只留中文」）。由于 AI 只作用于「原本无字幕」的音轨，不存在与官方字幕二选一的问题。

### 3.5 健壮性
- exe 缺失 / 模型未下载 / 无 GPU：友好 snack/对话框提示（含指向官方 release 与模型下载的帮助）。
- 支持取消（kill 子进程树）；退出码非 0 时展示 stderr 摘要。
- macOS 下需用户自装 Python + 依赖，`infer.exe` 不适用，暂以 Windows 优先（见第 4 节）。

---

## 4. 范围与优先级（已确认）

- **本轮**：仅调研方案，不写代码。
- **目标平台**：**Windows 优先**（ChickenRice 官方以 exe/bat 为主；macOS 二期）。
- **字幕策略**：**有同名 `.vtt`/`.lrc` 官方字幕就跳过 AI，仅对无字幕音轨翻译**；**只留中文**（不保留日文）。
- **触发**：下载后自动翻译（带开关）+ 手动按钮。

### 建议实施顺序（后续排期）
1. **P0**：`SubtitleGapDetector`（按「同名字幕是否存在」过滤音轨，纯文件系统、可单测）。
2. **P1**：ChickenRiceService（进程调用 + 参数拼接 + 进度解析）+ 配置项 + 手动/自动触发按钮。
3. **P2**：Navidrome 整理接入（AI 中文 lrc 嵌入标签；只留中文）。
4. **P3**：进度 UI 打磨、批量翻译、macOS 支持。

---

## 5. 待确认（实施前敲定）

1. **同名匹配范围**：确认「同名」覆盖 `foo.vtt` 与 `foo.mp3.vtt` 两种命名（复用整理逻辑现有 key 匹配方式）；是否需要额外匹配官方也可能下发的 `.srt`？
2. **自动翻译失败/耗时**：GPU 被占、单作品多小时是否要弹确认或排队？（默认静默异步 + 完成/失败 toast。）

---

## 6. 附录：ChickenRice 命令行示例（联动实际会拼的命令）

```bash
# Windows（工作目录必须为 exe 所在目录）
infer.exe \
  --device=auto \
  --task=translate \
  --sub_formats="lrc" \
  --audio_suffixes="wav,flac,mp3" \
  --output_dir="D:\\asmr\\RJ00000000\\ai_sub" \
  "D:\\asmr\\RJ00000000"
```

对应源码：`src/faster_whisper_transwithai_chickenrice/infer.py`（`parse_arguments` / `Inference.__init__` / `_scan` / `main`）。

---

## 7. 实现状态（2025-08）

本轮已完成方案落地（仅调研→执行）：

| 模块 | 文件 | 状态 |
|---|---|---|
| P0 字幕缺口检测 | `lib/services/transcribe/subtitle_gap_detector.dart` | ✅ 已完成 |
| P1 服务层 | `lib/services/transcribe/chicken_rice_config.dart` + `chicken_rice_service.dart` | ✅ 已完成 |
| P1 配置 providers | `lib/common/config_providers.dart` + `lib/services/transcribe/transcribe_providers.dart` | ✅ 已完成 |
| P1 配置装载 | `lib/pages/components/initialization.dart` | ✅ 已完成 |
| P1 UI | `chicken_rice_config_controls.dart` + `transcribe_button.dart` + `downloader.dart` 挂载 | ✅ 已完成 |
| P1 触发 | `ui_service.dart`（配置 setter + transcribe run + auto）+ `download_manager.dart`（自动触发） | ✅ 已完成 |
| P2 整理兼容 | 现有 `navidrome_organizer.dart` 的「同名 lrc 优先」已天然支持 AI lrc；补回归测试 | ✅ 已完成 |
| 测试 | `test/subtitle_gap_detector_test.dart`、`test/chicken_rice_service_test.dart`、`test/navidrome_organizer_test.dart` 增补 | ✅ 已编写 |
| 文档 | `README.md` 新增「AI 字幕翻译（ChickenRice 联动）」 | ✅ 已完成 |

### 实现说明
- **P2 无需改动 `navidrome_organizer.dart`**：AI 生成的 `<音轨>.lrc` 正好落到现有「同名 .lrc 优先于 vtt 转换」的最高优先级路径，且只作用于原本无字幕的音轨，与「只留中文」一致。
- **自动触发**：`download_manager` 的 completed 分支，`autoTranscribeProvider` 开启且 exe 配置好时调用 `uiService.autoTranscribe(sourceId)`。
- **工作目录**：`ChickenRiceService` 固定以 exe 所在目录为进程工作目录（ChickenRice 运行时 `os.chdir` 到该处找模型）。

### 验证备注
- `flutter analyze`（经 `dart analyze` snapshot）全项目 **No issues found**。
- **单元测试未能运行**：当前环境文件沙箱禁止写 `~/flutter/bin/cache`（workspace 外），`flutter test` 命令无法执行（升级权限无可用审批通道）。测试文件已编写好，需在具备 Flutter 工具链正常写权限的环境执行 `flutter test test/subtitle_gap_detector_test.dart test/chicken_rice_service_test.dart test/navidrome_organizer_test.dart` 验证。

---

## 8. 联动修正记录（2026-08）

联动上线后发现一批与 ChickenRice v1.10 联动的缺陷，已按 [docs/chickenrice-linkage-fix-plan.md](chickenrice-linkage-fix-plan.md) 修正：

| 问题 | 修复 | 状态 |
|---|---|---|
| P0-1 bat 模式 `pause` 挂死（stdin 未关闭） | `RealProcessRunner` 启动后立即 `stdin.close()` | ✅ |
| P0-2 中文 Windows 管道 GBK 输出 | 子进程注入 `PYTHONUTF8=1` + `Utf8Decoder(allowMalformed: true)` + 流 onError 兜底 | ✅ |
| P0-3 bat 模式 `--overwrite` 被 REMAINDER 吞掉 | `--overwrite` 移至目录参数之前 | ✅ |
| P0-4 每文件进度在 stderr 未被解析 | stderr 参与进度解析，文件级进度优先并提取当前文件名 | ✅ |
| P0-5 自动翻译无运行互斥 | `autoTranscribe` 增加 running 检查 | ✅ |
| P1-1 exe 默认 `audio_suffixes` 缺视频格式 | 与 `kAudioExtensions` 对齐（含 wma/视频/flv/wmv） | ✅ |
| P1-2 退出码 0 但 0 输出的假成功 | 解析 `找到 N 个文件待处理`/`未找到要处理的文件`，UI 给出可操作提示 | ✅ |
| P1-3 缺口检测漏视频 stem（`foo.mp4.vtt`） | `_hasSubtitle` targets 由 `kAudioExtensions` 泛化生成 | ✅ |
| P1-4 多目录被 `join(' ')` 拼成单参数 | `buildCommand(List<String> dirs)` 每目录独立 argv | ✅ |
| P2-1 macOS 不支持翻译 | 非 Windows 平台控件禁用 + probe 拦截（用户确认不做 .py 方案） | ✅ |
| resource/ 上传问题 | 加入 `.gitignore`（仅本地参考） | ✅ |
| P1-5 批量聚合一次进程 | `ui_service.transcribeWorks` 聚合缺口目录一次 `run(dirs:)`；批量「字幕所选」一次模型加载（中途取消终止整批，已确认接受） | ✅ |

