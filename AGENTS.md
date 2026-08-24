# AGENTS.md

asmr.one 的 GUI 下载工具（下载 + 作品库整理/AI 字幕）。本文所有命令与路径均来自仓库既有事实（README.md、docs/、.github/workflows/windows-release.yml）。

## 技术栈与目录结构要点

- **技术栈**：Flutter/Dart 桌面应用（`flutter` 依赖，pubspec `name: asmr_downloader`，`sdk: ^3.5.3`）；状态管理 flutter_riverpod，持久化 drift/sqlite + json_storage，网络 dio，日志 logger。平台目录 `windows/`、`macos/` 均存在；CI 固定 Flutter 3.41.3 stable（`.github/workflows/windows-release.yml`）。
- `lib/pages/`：页面与组件（`downloader/` 下载页、`media_library/` 作品库、`library/tools/` 整理/字幕工具、`window_title_bar/`、`onboarding/`、`update/`、`components/`）。
- `lib/services/`：按域分目录 —— `asmr_repo/`（API）、`download/`、`organize/`（Navidrome 整理/校验）、`transcribe/`（ChickenRice AI 字幕）、`library/`、`cache/`、`update/`、`engine/`、`ui/`。
- `lib/common/`（`const.dart`、`config_providers.dart`）、`lib/models/`、`lib/utils/`（含 `log.dart`）、`lib/ui/`。
- `test/`：顶层聚焦测试；`docs/`：设计/联调文档（如 `parallel-download-spec.md`、`chickenrice-*.md`）。

## 构建与发布

- Windows 发布构建：`flutter build windows --release`（README「构建与发布」+ CI）。
- macOS 发布构建：`flutter build macos --release`（README；要求 Xcode 27+，部署目标 macOS 12.0+）。
- 发布流程：推送 `v*` tag 触发 CI（工作流名 `AsmrDownloader Release Build`）自动构建 Windows + macOS 并发布 GitHub Release；手动触发：`gh workflow run "AsmrDownloader Release Build" --ref main -f version=vX.Y.Z`（README）。
- 静态检查：`flutter analyze`（docs 验收项，如 `chickenrice-linkage-fix-plan.md`）。

## 聚焦测试

- **命名约定**：`test/` 下按被测对象命名 `<subject>_test.dart`（如 `verify_service` → `test/verify_service_test.dart`）；同一对象按功能拆多文件（`ui_service` → `ui_service_search_test.dart` / `ui_service_snack_test.dart`）；禁用用例用 `.disabled.dart` 后缀（`test/cv_stats_test.disabled.dart`）。用例用中文描述「场景/行为」。
- **单文件聚焦示例**：`flutter test test/verify_service_test.dart`（整理校验链路；CI 亦使用同形态命令 `flutter test test/system_proxy_config_test.dart`）。
- 常用聚焦命令（文件均已存在）：`flutter test test/ui_service_search_test.dart`（ui_service）；`flutter test test/parallel_download_test.dart`（DownloadManager 并发/队列，配套 `download_queue_test.dart`、`download_cancel_test.dart`、`multi_thread_downloader_test.dart`）。

## 日志

- **文件位置**：`<应用数据目录>/debug/asmr_downloader.log`；macOS 为 `~/Library/Application Support/AsmrDownloader/debug/asmr_downloader.log`，Windows 保持应用目录内相对路径（`lib/utils/tool_functions.dart` 的 `getAppDataDir()`，详见 `lib/utils/log.dart`）。超过 5 MB 轮转为同路径 `.old`。开关入口：Debug 模式复选框（`lib/pages/downloader/config_settings/components/debug_mode_check.dart` → `ui_service.onDebugModeChanged` → `Log.setFileOutputEnabled`）。
- **内存缓冲入口**：`lib/utils/log.dart` 的 `Log.buffer`（`LogBuffer`，ChangeNotifier，上限 1000 条）；所有 `Log.*` 调用先写入缓冲，供应用内日志查看器（`lib/pages/components/log_viewer_dialog.dart`）。

## 核心变更路由：先用有界 git 历史核对，再采用证据 pack

- **前置核对（必做）**：在依赖 core-change-watch 证据 pack 的 `coreCandidates` / `followUpActions` 路由核心变更评审前，先用有界 git 历史统计变更频次：

  ```bash
  git log --since=90.days --name-only --format= | sort | uniq -c | sort -rn | head -20
  ```

- **判定**：把 pack 的 `coreCandidates` 与 git 变更频次前几位对比：
  - 一致 → 可按 pack 路由，并在评审输入注明「已与 git 热点核对一致」；
  - 不一致 → **以 git 热点为准**选择核心核检对象（模板/生成文件不得作为核心实现核检对象），并在评审输入中显式记录差异（pack coreCandidates vs git 热点、采用依据），不得静默沿用 pack 路由。
- **基线记录（2026-08-24 核对）**：pack coreCandidates 指向 `windows/flutter`、`windows/runner`（Windows 模板/生成文件）；90 天 git 热点前几位是 `lib/services/ui/ui_service.dart`（44 次提交）、`lib/services/download/download_manager.dart`（40 次提交），pack 自身 `historyProfile.supportingHotPaths` 也以 lib/pages（518 次）、lib/services（279 次）为最高。差异显式记录在 `docs/core-change-review-input.md`。

## 高频变更文件（核心核检对象，git 90 天热点排名）的注意边界

- **`lib/services/ui/ui_service.dart`**（git 90 天热点第 1，44 次提交；`lib/services/ui/ui_providers.dart` 暴露 `uiServiceProvider`）：全局 UI 动作聚合（搜索、配置开关、SnackBar、整理、AI 字幕、退出确认）。注意：无 BuildContext 场景走全局 `scaffoldMessengerKey` / `navigatorKey` 或 `showSnack`（无 messenger 时静默跳过）；配置改动经 `configFileProvider.addOrUpdate` 持久化并 `Log.info` 记录；测试模式用 `ProviderContainer(overrides:)`（见 `test/ui_service_search_test.dart`）。
- **`lib/services/download/download_manager.dart`**（git 90 天热点第 2，40 次提交；`lib/services/download/download_providers.dart` 暴露 `downloadManagerProvider`）：下载编排（run 循环、并行 worker、进度聚合）。注意：下载中允许搜索新作品，收尾写注册表必须用 `_RunContext` 快照值，不得重读全局 provider；`_runSeq` 抢占——新一轮 run 使旧一轮让位，旧流程不得覆盖新状态；取消走 `_cancelRequested` + CancelToken；并行/线程数压缩规则改动参考 `test/parallel_download_test.dart` 与 `docs/parallel-download-spec.md`；协作文件为 `download_queue.dart`、`multi_thread_downloader.dart`、`chunk_downloader.dart`。