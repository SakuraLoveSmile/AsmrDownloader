# ad20261109：应用内截图反馈 + 发布 v0.15.0

- 项目 / 任务编号：personal-asmrdownloader / ad20261109
- 状态：待体验（已发布 v0.15.0，等待用户确认）
- 创建日期（Asia/Taipei）：2026-11-09
- 权威记录：本文件
- 主仓库 / 当前工作目录：`/Users/sakurasep/Documents/Code/Project/Personal Project/AsmrDownloader`
- 基线 / 分支 / 合入目标：`main`（`248a2c7`）→ `main`
- 当前 HEAD / 未提交差异或快照：基线 `248a2c7` + 本次 feedback 改动（未提交部分见“提交与集成”）
- 运行资源：无端口/常驻服务；验证产物在 `build/macos/Build/Products/Release/`，反馈落盘到应用数据目录 `feedback/<时间戳>/`

## 目标与范围

用户能在下载页「设置 → 常规与调试」点「反馈」，在应用内对当前界面做截图标注 + 写文字说明，提交后保存到应用数据目录，并可一键打开该目录，把截图作为附件提交到 GitHub Issues。本次同时发布 `v0.15.0`（Windows + macOS）。

范围：`feedback` 3.2.0 依赖接入、`BetterFeedback` 包裹根 `MaterialApp`、设置面板入口、落盘服务与 UI 动作、对应测试、版本号与 tag 发布。
排除：反馈的自动上传（仍走人工 GitHub Issue）、与本次无关的未提交改动（`AGENTS.md`、`docs/*.md`、`.agent-teams/`）。

## 已确认决定

- 组件选型：`feedback` 3.2.0（pub 最新版），用法为 `BetterFeedback` 包裹 `MaterialApp`。
- 落盘格式：每次提交写 `<应用数据目录>/feedback/<yyyyMMdd_HHmmssSSS>/`，含 `screenshot.png` 与 `feedback.txt`（说明 + 版本 + 平台 + 时间 + Issue 入口）；时间戳带毫秒，避免同秒覆盖。
- 主题与文案：`BetterFeedback` 的 `themeMode` 跟随应用 `themeModeProvider`；`localeOverride` 锁定 `zh`（应用界面文案全中文，组件自带中文翻译）。
- 入口位置：随「日志」按钮放入设置面板「常规与调试」分组。
- 版本号：新功能 → `0.15.0`（沿用 0.13.0/0.14.0 的 minor 递增惯例）。
- 顺带修复（本次必需前置）：`openFolderForDir` 在 Windows 上把 `explorer "$dir"` 整条当作可执行名，`Process.run` 不走 shell 导致打不开目录；改为 `Process.run('explorer', [dir])`。「打开目录」是该功能的用户出口，故纳入本次。

## 实现与验收

| 步骤 | 用户效果 / 实现范围 | 验收情形与预期 | 当前结果及证据 | 状态 |
| --- | --- | --- | --- | --- |
| T1 | 设置面板出现「反馈」按钮 | 点按钮弹出截图标注浮层，文案为中文 | `test/feedback_button_test.dart` 通过（浮层出现且中文文案正确） | 待体验 |
| T2 | 提交后落盘截图与说明 | 目录含 `screenshot.png`、`feedback.txt`；同秒两次提交不覆盖 | `test/feedback_service_test.dart` 2 个用例通过 | 待体验 |
| T3 | 保存成功提示 + 「打开目录」 | 记录路径、平台与版本信息，Windows/macOS 均可打开目录 | 代码路径核对；真机按钮点击未在 Windows 验证 | 实现中 |
| T4 | 发布 `v0.15.0` | CI 构建 Windows + macOS 并生成 Release | Release 已发布，两个平台产物 + SHA256SUMS 齐备 | 待体验 |

## 执行与验证记录

| 日期 | 代码版本 / 候选差异 | 环境与运行对象 | 命令或实际操作 | 结果 / 证据位置 |
| --- | --- | --- | --- | --- |
| 2026-11-09 | 基线 `248a2c7` + feedback 改动 | macOS 26.x，Flutter 3.41.3 | `flutter analyze` | No issues found |
| 2026-11-09 | 同上 | 同上 | `flutter test` | 510 个用例全部通过（无失败） |
| 2026-11-09 | 同上 | 同上 | `flutter build macos --release` | 构建成功，`AsmrDownloader.app` 52.8MB |
| 2026-11-09 | 同上 | 同上 | 启动 Release 构建，检查进程与日志 | 应用正常启动，日志无 feedback 相关报错 |
| 2026-11-09 | `b921d57`（含 v0.15.0 tag） | GitHub Actions（ubuntu / windows-latest / macos-latest） | `git push origin main`、`git push origin v0.15.0` | CI 运行 42611725042 成功；Release 运行 42611788174 全绿（quality-gate / build-windows / build-macos / release） |
| 2026-11-09 | Release `v0.15.0` | GitHub Release | `gh release view v0.15.0` | 产物：Windows.zip 15.0MB、macOS.zip 21.6MB、SHA256SUMS |

说明：截图提交链路在 widget 测试中依赖组件内部真实异步截屏，测试仅覆盖入口与落盘服务边界；完整“标注 + 提交 + 打开目录”需真机人工体验确认。

## 提交与集成

| 提交 | 行为变化与原因 | 验证 | 合并 / 发布情况 |
| --- | --- | --- | --- |
| `feat(feedback): 接入应用内截图反馈入口`（`4aef193`） | 新增反馈入口与落盘服务；修复 Windows 打开目录 | analyze / test / macOS 构建 | 已推送到 `main` |
| `chore: release v0.15.0` | 版本号 0.14.1 → 0.15.0 | 同上 | 已推送到 `main`；签名 tag `v0.15.0` 触发 Release 构建并发布成功 |
