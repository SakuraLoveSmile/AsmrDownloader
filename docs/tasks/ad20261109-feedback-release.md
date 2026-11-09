# ad20261109：接入个人灵感球反馈组件 + 发布

- 项目 / 任务编号：personal-asmrdownloader / ad20261109
- 状态：待体验（已发布 v0.16.1，等待用户确认）
- 创建日期（Asia/Taipei）：2026-11-09
- 权威记录：本文件
- 主仓库 / 当前工作目录：`/Users/sakurasep/Documents/Code/Project/Personal Project/AsmrDownloader`
- 基线 / 分支 / 合入目标：`main`（`248a2c7`）→ `main`
- 当前 HEAD / 未提交差异或快照：`f9e9b38`（v0.16.1）；本次改动均已提交
- 运行资源：无端口/常驻服务；验证产物在 `build/macos/Build/Products/Release/`；反馈提交到 Feedback 服务（生产地址）

## 目标与范围

用户能在应用内用个人「灵感球」反馈组件提交反馈：点球或拖球到问题位置截图，在面板里写说明并提交到 Feedback 服务，由后台 AI 整理后归档到 Kaneo。

**范围变更（2026-11-10）**：最初误接了 pub.dev 第三方 `feedback` 3.2.0（普通按钮 + 本地落盘 + 手动传 GitHub Issue），经用户指出后改接个人 Feedback 项目的 `feedback_widget`，本地落盘方案整体移除。

范围：`feedback_widget` 0.9.0 接入（`MaterialApp` 外侧挂载 + 根持有 `FeedbackController`）、灵感球、`captureAndOpen()` 宿主入口、服务身份配置、对应测试、版本号与 tag 发布。
排除：与本次无关的未提交改动（`AGENTS.md`、`docs/*.md`、`.agent-teams/`）。

## 已确认决定

- 组件选型：个人 Feedback 项目的 `feedback_widget`（git 依赖 + `flutter/feedback` 子目录，不发布 pub.dev），与 Music / MediaPlayer 一致。
- 挂载位置：`FeedbackWidget` 包在 `MaterialApp` 外侧——截图边界提升到根 Navigator/Overlay 之上，`showDialog` 默认的根弹窗也入图。
- 控制器：`FeedbackController` 由根 provider 持有，容器 dispose 时释放；页面只读取调用。
- 配置：显式 `launcherMode: orb` + `captureMode: viewport`（包默认 tab/off）；`launcherBottom: 30%` 避开右下角任务浮条；`themeMode` 跟随 `themeModeProvider`；`pageLabel` 由页面索引收敛为固定分类，不上报路由/搜索词。
- 服务身份：`--dart-define` 可覆盖，默认 `https://feedback.xn--fhqths51enha.cn` + appId `asmrdownloader`；debug 与测试构建默认不挂载。
- 入口：侧边栏底部固定「反馈」按钮调用 `captureAndOpen()`（灵感球本身也是常驻入口）。
- 版本号：`0.15.0`（误接版本）→ `0.15.1`（入口位置修正）→ `0.16.0`（换灵感球）→ `0.16.1`（依赖 commit 修正）。
- 顺带修复（已作废）：`openFolderForDir` 的 Windows 参数修复随本地落盘方案一并移除后仍保留在代码中，作为独立缺陷修复有效。

## 实现与验收

| 步骤 | 用户效果 / 实现范围 | 验收情形与预期 | 当前结果及证据 | 状态 |
| --- | --- | --- | --- | --- |
| T1 | 灵感球常驻右侧，可拖拽指出问题 | 球在场、56dp、停靠右侧；拖球松手进入局部选区 | `test/feedback_orb_mount_test.dart`（3 用例）；应用内元素树探针实测 `feedback-orb-body` 56×56 @ (964, 404.6) | 待体验 |
| T2 | 点球/按钮呼出面板并截当前视口 | 面板打开、截图带敏感区遮挡、提交到服务 | 组件自带 668 用例通过；真实提交未验证 | 实现中 |
| T3 | 侧边栏「反馈」按钮作为显式入口 | 默认窗口下可见可点，未启用时隐藏 | `test/feedback_button_widget_test.dart`（2 用例） | 待体验 |
| T4 | 发布 v0.16.1（Windows + macOS） | CI 两平台构建通过并生成 Release | Release run 42668385310 全绿，产物齐备 | 待体验 |

## 执行与验证记录

| 日期 | 代码版本 / 候选差异 | 环境与运行对象 | 命令或实际操作 | 结果 / 证据位置 |
| --- | --- | --- | --- | --- |
| 2026-11-10 | `0e430a3`（换灵感球） | macOS，Flutter 3.41.3 | `flutter analyze` | No issues found |
| 2026-11-10 | 同上 | 同上 | `flutter test` | 518 个用例通过（新增灵感球挂载 3 例） |
| 2026-11-10 | 同上 | 同上 | `flutter build macos --release` | 成功 55.0MB |
| 2026-11-10 | 同上 | 同机运行 release 构建 | 元素树探针（临时，已移除） | `feedback-orb-body` size=56×56 pos=(964, 404.6)，`feedback-launcher-slot` 同尺寸；控制台无异常 |
| 2026-11-10 | `v0.16.0` tag | GitHub Actions | Release 构建 42664059960 | **build-windows 失败**：`flutter pub get` 报 `Error on line 2, column 21: Unexpected character`；build-macos 通过 |
| 2026-11-10 | Sakura-Feedback `8edc2be` | 本地 worktree | 组件包 `flutter pub get` / `flutter analyze` / `flutter test` | 通过；包测试 668 用例全绿；pubspec 被解析值全部 ASCII |
| 2026-11-10 | `b36ab70`（ref 指向 8edc2be） | macOS | `flutter pub get` / `flutter analyze` / `flutter test` | 锁定到 8edc2b；analyze 无问题；518 用例通过 |
| 2026-11-10 | `v0.16.1` tag | GitHub Actions | Release 构建 42668385310 | quality-gate / build-windows / build-macos / release **全部成功**；产物 Windows 15.4MB、macOS 22.4MB、SHA256SUMS |

**Windows 构建失败的根因**：组件包 `flutter/feedback/pubspec.yaml` 的 `description` 为中文，Windows 下 Dart pub 按系统代码页（GBK）解码该字段后解析失败。与宿主无关（Music / MediaPlayer 未在 Windows CI 上跑到该依赖路径）。修复为 ASCII description 后 Windows 构建通过。

## 提交与集成

| 提交 | 行为变化与原因 | 验证 | 合并 / 发布情况 |
| --- | --- | --- | --- |
| `4aef193` feat(feedback) | 误接 pub `feedback` 3.2.0（本地落盘） | analyze / test / macOS 构建 | v0.15.0 已发布 |
| `2e9d4a4` fix(feedback) | 入口从设置面板移到侧边栏底部（原位置在首屏外） | 新增 widget 测试 | v0.15.1 已发布 |
| `0e430a3` feat(feedback) | 换用个人 `feedback_widget` 灵感球，移除本地落盘 | analyze / test 518 / macOS 构建 / 元素树实测 | v0.16.0（Windows 失败，未发布） |
| `b36ab70` fix(feedback) | ref 指向修复 Windows pub get 的组件 commit `8edc2be` | analyze / test 518 | v0.16.1 已发布 |
| Sakura-Feedback `8edc2be` | 组件包 pubspec description 改 ASCII | 包测试 668 / analyze | 已推送 Feedback main |
