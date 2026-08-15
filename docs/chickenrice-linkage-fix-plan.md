# AsmrDownloader × ChickenRice 联动修正计划

> 状态：调研 + 验证完成 → **已全部实施**（2026-08，含 P1-5 批量聚合）。
> 2026-08 更新（按用户决定）：macOS 不支持翻译功能（整体禁用，不做 .py 方案）；resource/ 仅本地参考，加入 .gitignore 不上传远程仓库。
> 实施记录见 docs/chickenrice-integration-plan.md 第 8 节。
> 调研对象：resource/Faster-Whisper-TransWithAI-ChickenRice（git clone，固定于上游 main @ 6210488，即 v1.10 + 1 提交，2026-07-05；resource/ 当前未被主仓库跟踪）
> 联动代码：lib/services/transcribe/*、lib/pages/library/tools/*、lib/services/ui/ui_service.dart

---

## 1. 调研结论（事实核对）

| # | 事实 | 出处 | 对联动的影响 |
|---|---|---|---|
| 1 | ChickenRice 纯 CLI，无 RPC；入口 infer.exe（PyInstaller，内置 Python 3.10，见 CI build-windows.yml）或 python infer.py；bat 只是拖放包装 | infer.py / 使用说明.txt | 联动必须走进程调用 + 参数 + 文件系统 |
| 2 | 关键参数均存在：`--device/--task/--sub_formats/--audio_suffixes/--overwrite/--model_name_or_path/--output_dir/--log_level`，base_dirs 为 `nargs=argparse.REMAINDER` | src/.../infer.py:88-198 | exe 模式参数拼接基本正确 |
| 3 | 输出命名 = `<音轨stem>.<fmt>`（foo.wav → foo.lrc），与音轨同目录；已存在且未加 `--overwrite` 时按格式跳过 | infer.py:1274-1306 | 与 SubtitleGapDetector / Navidrome 同名 lrc 链路一致 ✅ |
| 4 | 运行时 `os.chdir` 到脚本所在目录，VAD 模型硬编码 `models/whisper_vad.onnx`，主模型默认 `models` | infer.py / vad_manager | 服务已用脚本目录作工作目录 ✅ |
| 5 | **日志走 stderr**：`logger = logging.StreamHandler()`（默认流 = sys.stderr），控制台级别 = `--log_level`（默认 DEBUG）。每文件进度 `正在处理（task，n/total）：path`、文件计数 `找到 N 个文件待处理`、`未找到要处理的文件` 全在 stderr | infer.py:554-557, 1602 | **App 只解析 stdout，拿不到每文件进度与文件计数** ❌ |
| 6 | stdout 只有：声明横幅、VAD 进度（`\r` 刷新 + flush，最终 `print()` 换行） | infer.py:741-758 | Dart LineSplitter 会把 `\r` 当行分隔（已验证），VAD 进度可实时到达 ✅ |
| 7 | 所有 bat 结尾都有 `pause`；bat 用 `%*` 透传参数 | 各 .bat | **非交互 stdin 下 pause 会阻塞** ❌（见问题 1） |
| 8 | 内置 Python 3.10：Windows 下 stdout/stderr 为管道时按 locale 编码（中文系统 = GBK/cp936）输出，chcp 65001 不影响管道编码 | CI python-version: 3.10；PEP 528/540/597 | **App 用 utf8.decoder 严格解码会抛 FormatException；横幅含 ⚠️ 等 GBK 无法编码字符，print 直接 UnicodeEncodeError 崩溃** ❌（见问题 2） |
| 9 | 进程 stdin：Dart Process.start 不自动关闭子进程 stdin（本地实测：不 close 时子进程 `read` 永久阻塞 4s 超时被杀；显式 `p.stdin.close()` 后 24ms 完成） | 本机 Dart 实测 | 见问题 1 |

---

## 2. 问题清单（按严重度）

### P0-1 bat 模式运行永远不结束（pause 挂死）——联动主路径失效

- 链路：`cmd.exe /d /c call xxx.bat <dir>` → bat 末尾 `pause` 从 stdin 等待按键；Dart 侧 stdin 管道写端一直打开且不写数据 → pause 永久阻塞 → `_await` 永远等不到 exitCode。
- 症状：进度停在最后状态、UI 永远「运行中」；用户点取消后 taskkill 杀掉整棵树，`_await` 返回 false → 即使翻译实际已全部完成，也提示「字幕翻译失败或已取消」。
- 依据：本地 Dart 子进程实测（不 close stdin → 阻塞；close → EOF 立即返回）。
- **修复**：`RealProcessRunner.start` 在 `Process.start` 成功后立即 `process.stdin.close()`（对 Windows pause 与任何读 stdin 的子进程均为 EOF 语义，pause 读到 EOF 立即返回）。

### P0-2 中文 Windows 下管道输出编码不匹配（GBK vs UTF-8）

- 链路：infer.exe（Python 3.10，管道输出）在中文 Windows 按 cp936 编码 stdout/stderr；App 以 `utf8.decoder`（allowMalformed=false）解码。
- 症状：① 启动横幅 `⚠️ 重要声明` 的 ⚠️ 在 GBK 下 `print` 直接抛 UnicodeEncodeError → infer.exe 启动即崩溃（退出码 1）；② 即使不崩，含中文的日志行解码抛 FormatException → 进度解析监听无 onError → 解析中断/未捕获错误。
- 依据：Python 3.10 管道编码规则（非 UTF-8 模式按 locale）；CI 确认内置 3.10。需在中文 Windows 上最终验证。
- **修复**（双保险）：
  1. `ProcessRunner.start` 增加 `environment` 参数，真实实现注入 `PYTHONUTF8=1`（PEP 540，强制 stdio 用 UTF-8；兼容 Python 3.10，bat 模式经环境继承传给 infer.exe）；
  2. 解码统一改为 `utf8.decoder(allowMalformed: true)`（坏字节不中断解析），并为 stdout/stderr 监听加 onError 兜底。

### P0-3 bat 模式 `--overwrite` 静默失效

- 链路：bat 模式命令为 `call bat.bat <dirs> --overwrite`，bat 经 `%*` 透传后 `--overwrite` 落在位置参数之后；ChickenRice 的 base_dirs 是 `argparse.REMAINDER`，会**吞掉后续所有 token（含 `--overwrite`）**并入 base_dirs（已用 argparse 复现实测：overwrite=False，base_dirs 含 '--overwrite'）；`_scan` 对无扩展名的 `--overwrite` 直接跳过 → 完全无提示。
- 症状：用户想覆盖重翻时无效，还多出一个幽灵路径参数。
- **修复**：bat 模式把 `--overwrite` 放到 dirs **之前**（`call bat.bat --overwrite <dir1> <dir2>`；bat 的 `%~1` 非空仍走直接运行分支，`%*` 展开后 flag 在位置参数前，argparse 正确解析）。同步修正当前断言「--overwrite 在末尾」的单测。

### P0-4 进度解析错位：每文件进度在 stderr 而 App 只看 stdout；currentFile 永远为空

- 事实：stdout 仅有 VAD 分块进度（`x/y` 块），且 LineSplitter 已按 `\r` 分行 → VAD 进度可实时更新（此点没问题）；但「正在处理第几个文件（n/total）」走 logger → stderr，App 的 `_await` 只对 stdout 调 `_parseProgress`。
- 症状：单作品多音轨时总进度只能在 VAD 块间跳动、看不到「第 n/total 个文件」；`TranscribeProgress.currentFile` 恒为 ''。
- **修复**：
  1. `_await` 对 stderr 同样挂 `_parseProgress`（stderr 仍保留错误尾部收集）；
  2. `_parseProgress` 优先匹配每文件进度行（zh：`正在处理（…，{n}/{total}）：{path}`；en：`Processing ({task}) ({n}/{total}): {path}`），提取 currentFile（path 末段）；
  3. VAD 行仅作为文件内次级进度，避免百分比回跳（进度优先级：文件级 n/total > VAD x/y）。

### P0-5 自动翻译无「运行中」互斥，并行下载会并发启动多个 ChickenRice

- 事实：手动 `transcribeWork` 有 `TranscribeStatus.running` 检查；`autoTranscribe`（下载完成触发）没有。
- 症状：多个下载几乎同时完成 → 多个 infer.exe 并发跑（模型重复加载、显存/算力争抢、Provider 状态互相覆盖）。
- **修复**：`autoTranscribe` 开头加 running 检查（与 transcribeWork 一致，占用则 Log 跳过）；若需排队可二期做任务队列。

---

### P1-1 exe 模式默认 `audio_suffixes` 与缺口检测不一致 → 假成功

- 事实：配置默认 `wav,flac,mp3,m4a,aac,ogg`（无视频）；`SubtitleGapDetector.kAudioExtensions` 与 bat 均含 `mp4/mkv/avi/mov/webm`（bat 还含 wma/flv/wmv）。ChickenRice 对「缺口检测认为缺字幕、但后缀不在 audio_suffixes」的文件直接跳过，**找不到文件时仍退出码 0**（stderr 只有 `未找到要处理的文件`）。
- 症状：纯视频作品在 exe 模式下提示「字幕翻译完成」，实际什么都没生成。
- **修复**：
  1. 默认 `audioSuffixes` 与 `kAudioExtensions` 对齐（补 `wma,mp4,mkv,avi,mov,webm,flv,wmv`）；
  2. `kAudioExtensions` 补 `.flv/.wmv`（bat 已有）；
  3. 见 P1-2 的「0 输出」检测兜底。

### P1-2 成功但 0 输出的假成功（无输出检测）

- **修复**：`_await` 同时解析 stderr 的 `找到 N 个文件待处理` / `Found N file(s) to process` 与 `未找到要处理的文件` / `No files found to process`（中英文案），把「处理文件数」放进 `TranscribeResult`；`transcribeWork/autoTranscribe` 在 exit 0 但 0 文件时提示「未找到需处理的文件（检查音频格式/后缀配置）」而非「完成」。可选加固：运行后对比目录内新生成的 lrc。

### P1-3 `SubtitleGapDetector._hasSubtitle` 的 targets 漏视频 stem

- 事实：`_hasSubtitle` 的 targets 硬编码音频扩展名（`$stem.wav`…），不含视频 → `foo.mp4` 已存在 `foo.mp4.vtt` 时仍判定「缺字幕」→ 重复翻译。
- **修复**：targets 由 `kAudioExtensions` 泛化生成（或对视频也加同名 stem 匹配），并补对应单测。

### P1-4 多目录参数拼接缺陷（批量聚合的前置阻塞）

- 事实：`buildCommand(String dirs)` 把多个目录 `join(' ')` 成一个 argv 元素 → 含空格路径即断；UI 目前只用单目录（runOnDir）所以只是潜伏。
- **修复**：`buildCommand/run` 改为 `List<String> dirs`，每个目录作为独立 argv 元素传递（bat 模式经 `%*` 天然保留各参数引号；exe 模式同理），并补多目录单测。

### P1-5 「字幕所选」批量 = N 次进程启动 = N 次模型加载（✅ 已实施）

- 事实：work_list 批量循环逐个 `transcribeWork`，每次 spawn 都重新加载 Whisper 模型（分钟级 + 显存抖动）。
- **修复**（依赖 P1-4）：`ui_service` 新增 `transcribeWorks`，批量时先把所有选中作品的「缺口目录」聚合，一次 `run(dirs: [...])`（ChickenRice 原生支持多 base_dirs 且增量跳过）；`work_list._transcribeSelected` 改走聚合入口。单作品行内按钮仍走 `transcribeWork`（内部委托同一聚合方法）。代价：中途取消终止整批（用户已确认接受）。

---

### P2-1 非 Windows 平台：翻译功能整体禁用（用户已确认 macOS 不支持）

- 决定：macOS/其他平台不支持 AI 翻译功能，不做 `.py` 调用方案。
- **修复**：`probeScript` 在非 Windows 时返回明确错误「AI 翻译仅支持 Windows」；`ChickenRiceConfigControls` 在非 Windows 平台禁用/隐藏（含「自动」开关）；`transcribeWork/autoTranscribe` 入口统一拦截并提示。

### P2-2 失败诊断增强（可选）

- `_await` 失败时目前只取 stderr 尾 8 行；可改为收集含 ERROR/WARNING 的关键行并写入 `TranscribeResult.error`，UI snack 展示首条关键错误。

### P2-3 models 目录预检（可选）

- `probeScript` 对 exe 模式检查脚本目录下 `models/` 是否存在，不存在则提示先下载模型（否则首次运行才暴露）。

---

## 3. 修改文件清单（实施阶段）

| 文件 | 变更 |
|---|---|
| lib/services/transcribe/chicken_rice_service.dart | stdin close；environment（PYTHONUTF8）；allowMalformed 解码 + onError；stderr 进度解析 + 文件级进度/currentFile；多目录 argv；overwrite 位置修正（bat）；无输出检测（TranscribeResult 扩展） |
| lib/services/transcribe/chicken_rice_config.dart | audioSuffixes 默认值对齐（视频 + wma/flv/wmv） |
| lib/services/transcribe/subtitle_gap_detector.dart | targets 泛化（视频 stem）；kAudioExtensions 补 .flv/.wmv |
| lib/services/ui/ui_service.dart | autoTranscribe running 互斥；批量聚合 run(dirs:)；0 输出提示 |
| lib/pages/library/work_list.dart | 批量字幕：聚合缺口目录一次运行（✅ 已实施，`transcribeWorks`） |
| lib/pages/library/tools/chicken_rice_config_controls.dart | 非 Windows 禁用/隐藏控件；提示文案（bat 模式 overwrite/进度说明） |
| .gitignore | 追加 `resource/`（本地参考，不上传远程仓库） |
| test/chicken_rice_service_test.dart | 修正 overwrite 位置断言；新增：stdin close、环境变量、stderr 进度解析、多目录、无输出检测 |
| test/subtitle_gap_detector_test.dart | 视频 stem 匹配、flv/wmv |
| README.md | AI 字幕章节补充：进度/取消行为、编码与环境变量说明 |
| docs/chickenrice-integration-plan.md | 追加「修正记录」章节链接本计划 |

> 本轮（按用户要求）**不执行**上述修改。

---

## 4. 验证方式（实施后）

1. `flutter analyze` 全项目无告警；`flutter test test/chicken_rice_service_test.dart test/subtitle_gap_detector_test.dart` 通过。
2. macOS 本机：Dart 子进程 stdin EOF 行为回归（read 立即返回）。
3. Windows 真机（中文系统）：
   - bat 模式跑一个作品 → 无 pause 卡死、正常结束提示「完成」；
   - 日志中文无乱码、进度含「第 n/m 个文件」；
   - 批量选 2 个作品 → 仅一次模型加载（进程只 spawn 一次）；
   - `--overwrite`（改配置为 true）→ 重跑不跳过已存在字幕。

## 5. 已确认与待确认

已确认：
1. **macOS 不支持翻译功能**：不做 `.py` 调用方案；非 Windows 平台整体禁用 AI 字幕功能（控件禁用 + 入口拦截 + 明确提示），见 P2-1。
2. **resource/ 只是本地参考**：加入 `.gitignore`，不上传远程仓库（不转 submodule）。

待确认：
- ~~批量聚合（P1-5）~~ → **已确认并实施**（用户确认可一次请求多个选中作品，中途取消终止整批已接受）。
