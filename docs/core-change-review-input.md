# 核心变更评审输入：pack 与 git 热点核对记录

本文件是 core-change-watch 证据 pack 路由核心变更**之前**的核对记录（评审输入的一部分），由 `AGENTS.md`「核心变更路由」一节强制维护。

核对规则（每次依赖 pack 路由核心变更前必做）：

```bash
git log --since=90.days --name-only --format= | sort | uniq -c | sort -rn | head -20
```

- pack `coreCandidates` 与 git 变更频次前几位一致 → 可按 pack 路由，并注明「已与 git 热点核对一致」。
- 不一致 → **以 git 热点为准**选择核心核检对象，并把差异记录到本文件，不得静默采用 pack 路由。

## 当前基线记录（2026-08-24）

| 项目 | 内容 |
| --- | --- |
| 证据 pack | core-change-watch evidence pack（`.qoder/better-harness-runs/2026-08-24-185402-asmrdownloader/lane-project.json`） |
| pack `coreCandidates` | `windows/flutter`（score 46，hot 5 次提交）、`windows/runner`（score 41，hot 2 次提交）——Windows 模板/生成文件 |
| git 90 天热点前几位 | `lib/services/ui/ui_service.dart`（44 次提交）、`lib/services/download/download_manager.dart`（40 次提交） |
| pack 自身支持路径信号 | `historyProfile.supportingHotPaths`：lib/pages（518 次）、lib/services（279 次） |
| 差异结论 | **不一致**——pack 把核心注意力路由到模板/生成文件，真实热点在 Dart 服务层 |
| 采用对象 | 以 git 热点为准：`ui_service.dart`、`download_manager.dart`（及其协作文件 `download_queue.dart`、`multi_thread_downloader.dart`、`chunk_downloader.dart`） |
| 依据 | `.qoder/better-harness/2026-08-24/185402-asmrdownloader/findings.json` 的 `evidence-pack-core-misroute` 核实；`lane-project.json` 的 `coreAnalysis` / `diffImpact.companionHits` / `historyProfile.supportingHotPaths` |

## 记录模板（后续每次核对使用）

```markdown
- 日期 / 历史窗口：
- pack coreCandidates：
- git 90 天热点前几位（命令输出）：
- 是否一致：一致 / 不一致
- 采用对象（不一致时以 git 热点为准）：
- 差异说明（不一致时必填）：
```