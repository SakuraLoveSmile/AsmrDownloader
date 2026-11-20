# asmr-ci01：修复 KaneoPilot 发布脚本的 draft 回读失败

- 项目 / 任务编号：personal-asmrdownloader / asmr-ci01
- 状态：实现中（本地验证通过，等待 PR 合入与真实 Actions 复核）
- 创建日期（Asia/Taipei）：2026-11-20
- 权威记录：本文件
- 基线 / 分支 / 合入目标：`main`（`ebc8384`）→ `fix/20261120-asmr-ci01-pilot-release-draft-readback` → `main`
- 工作树：`/Users/sakurasep/Documents/Code/Project/Project Worktree/personal-asmrdownloader/20261120-fix-asmr-ci01-pilot-release-draft-readback`
- 运行资源：无端口/常驻服务；真实发布由 GitHub Actions 的 `AsmrDownloader Release Build` 工作流执行

## 目标与范围

KaneoPilot 为任务 `dljelzwybu94449pjrdx8dgx`（更新状态显示位置疑似过多）派发的预发布批次
`756655ff-51be-4cfd-a3c6-af0ab23e3665`（tag `v0.16.2-pilot.1795079423`）在
[run 44494500579](https://github.com/SakuraLoveSmile/AsmrDownloader/actions/runs/44494500579) 失败：
quality-gate、build-macos、build-windows 全绿，只有 release job 的 Publish Release 报
`Release 创建后无法读回`。

范围：只修 `.github/scripts/pilot_release.py` 的发布写入路径（创建/复用 draft、上传资产、发布后校验）。
排除：版本号、工作流输入契约、KaneoPilot 侧代码与发布策略。

## 已确认事实（根因）

- `gh release create --draft` 成功后，脚本用 `GET /releases/tags/{tag}` 回读；GitHub 的该端点
  **不返回 draft**（实测 404），于是 `require(isinstance(release, dict), 'Release 创建后无法读回')` 立即抛错。
- 现场留下的 draft：Release id `451114626`，tag `v0.16.2-pilot.1795079423`，0 个资产，无 tag ref。
- `gh release upload <tag>` 同样按 tag 解析，draft 场景不可依赖；因此上传也必须改成按 Release id。

## 实现

| 变更 | 说明 |
| --- | --- |
| `create_draft()` | 改为 `POST /releases` 直接拿回 Release 身份（id），不再依赖创建后的二次查询 |
| `draft_by_tag()` | draft 只能从 `GET /releases` 列表里按 tag 找；按 tag 读不到不等于没有 |
| `ensure_assets()` | 按 id 逐个资产对齐：size+sha256 一致就跳过，不一致先删后传；不再用 `gh release upload --clobber` |
| `publish()` | 复用同 tag 且 target_commitish 与本次 target_sha 一致的 draft；不一致明确拒绝，不覆盖 |
| `api_json(headers=...)` | 显式 `Content-Type: application/json`（创建/PATCH），资产上传用 `application/octet-stream` |

发布后仍走原有 `verify_release`：draft 关闭、tag 指向 target_sha、四个资产 size/digest/下载地址、清单字节逐一复核。

## 验证

| 检查 | 命令/方式 | 结果 |
| --- | --- | --- |
| 语法 | `python3 -m py_compile .github/scripts/pilot_release.py` | 通过 |
| 逻辑（全新批次） | 本地 in-memory GitHub 桩：无同名 Release → 建 draft → 3 个资产 → 发布 → 校验 | 通过 |
| 逻辑（断点重跑） | 桩内已有同 tag 同 target 的 draft + 1 个过期资产 → 复用同一 id、替换资产、不新建 Release | 通过 |
| 逻辑（拒绝误用） | 桩内 draft 的 target 是别的 SHA → 明确报错，不覆盖 | 通过 |
| 逻辑（重复发布） | 已发布且字节一致 → 幂等返回 | 通过 |
| 真实 Actions 运行 | 未运行（需合入 main 后由 KaneoPilot 重新派发） | 未验证 |

## 遗留

- 现场空 draft `451114626` 未处理：按 KaneoPilot `docs/release-contract.md` 的保留策略，测试预发布与标签不自动删除，清理须单独授权。
- 本修复合入后 main 头部再次变化，KaneoPilot 重新准备发布时需要针对新 target 走一次独立发布补验证。
