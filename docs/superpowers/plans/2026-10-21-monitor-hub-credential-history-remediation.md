# Monitor Hub 凭据历史清理实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在保留可恢复镜像备份的前提下，从 `monitor-hub` 全部受影响 Git 历史中移除旧 `vmware/config.yml`，并安全更新远端引用。

**Architecture:** 历史重写在独立 mirror 克隆中执行，不直接拿日常工作区冒险。先记录远端引用并验证备份，再删除所有历史中的旧敏感路径、验证对象库和内容扫描，最后使用带 lease 的明确引用强推；任何前置条件失败都停止。

**Tech Stack:** Git、SSH、Bash、内置 `git filter-branch`、仓库 secret 测试。

**Spec:** `docs/superpowers/specs/2026-10-21-monitor-hub-repository-design.zh-CN.md` 第 12.1 节

## Global Constraints

- 必须先得到“vCenter 暴露密码已经更换”的明确确认。
- 用户已授权执行历史清理，但强推前仍要核对远端 SHA 未发生意外变化。
- 备份目录固定为 `/Users/hua/Documents/Codex/IT-Code/remote/monitor-hub-history-backup-20261021.git`；若已存在则停止，不覆盖。
- 重写目录固定为 `/Users/hua/Documents/Codex/IT-Code/remote/monitor-hub-history-rewrite-20261021.git`；若已存在则停止，不覆盖。
- 只删除历史路径 `vmware/config.yml`；不得删除迁移后的脱敏组件配置。
- 不使用通配 refspec 强推；分支和标签逐项审计后显式推送。
- 远端更新失败时保留备份与重写 mirror，禁止自动重试强推。

## Review Focus

- 密码尚未更换时必须停止，即使用户已授权历史重写；由 Task 1 的前置检查固定。
- 远端 main 在记录 SHA 后发生变化时 lease 必须拒绝强推；由 Task 3 的模拟测试固定。
- 备份不完整或 `git fsck` 失败时不得开始重写；由 Task 1 固定。
- 重写后旧路径或 secret 模式仍存在时不得推送；由 Task 2 固定。
- 未受影响的文件、提交顺序和标签语义必须保留；由 Task 2 的树比较固定。

---

### Task 1: 记录前置确认并创建不可覆盖备份

**Files:**
- Create: `docs/security/credential-incident-2026-10.md`
- Create: `tests/security/history-remediation.bats`
- Create outside repository: `/Users/hua/Documents/Codex/IT-Code/remote/monitor-hub-history-backup-20261021.git`
- Create outside repository: `/Users/hua/Documents/Codex/IT-Code/remote/monitor-hub-history-rewrite-20261021.git`

**Interfaces:**
- Consumes: 用户对密码已更换的明确确认、当前本地 `main`、远端 `origin` refs。
- Produces: 事件记录、历史验证测试、`PRE_REWRITE_MAIN_SHA`、通过 `git fsck` 的 mirror 备份和独立重写 mirror。

- [ ] **Step 1: 确认密码已更换**

在 `docs/security/credential-incident-2026-10.md` 只记录确认日期、受影响路径、处理范围和“不保存旧密码”；不得写入旧值、新值或任何凭据片段。没有明确确认则停止整个计划。

- [ ] **Step 2: 编写历史清理验证测试并确认当前历史失败**

测试接受 `MH_HISTORY_BACKUP` 和 `MH_HISTORY_REWRITE` 两个 mirror 路径，断言所有重写 refs 中 `git log --all -- vmware/config.yml` 无结果；所有可达 blob 不包含已赋值的 `vsphere_password`；当前树仍包含脱敏后的 `components/vmware-exporter/`；备份 mirror 仍可读取原 refs。先对当前仓库运行旧路径检查，Expected: FAIL，证明测试能够识别待清理历史。

- [ ] **Step 3: 提交事件记录和验证测试**

```bash
git add docs/security/credential-incident-2026-10.md tests/security/history-remediation.bats
git commit -m "security: document and test credential remediation"
```

- [ ] **Step 4: 记录远端引用**

Run: `git ls-remote --heads --tags origin`
Expected: 保存输出到受限权限的本地审计文件，明确记录 `refs/heads/main` 的 `PRE_REWRITE_MAIN_SHA`。

- [ ] **Step 5: 创建两个 mirror 克隆**

从包含全部待发布提交的本地仓库分别创建 backup mirror 和 rewrite mirror；目标存在时命令必须失败，不删除或覆盖已有目录。创建后把 rewrite mirror 的 `origin` 明确设为 `git@github.com:robotneo/monitor-hub.git`，backup mirror 不配置可写 GitHub remote。

- [ ] **Step 6: 验证备份**

Run: `git -C /Users/hua/Documents/Codex/IT-Code/remote/monitor-hub-history-backup-20261021.git fsck --full`
Expected: 无 missing、dangling corruption 或 invalid object 错误。

### Task 2: 在隔离 mirror 中重写并验证历史

**Files:**
- Modify outside repository: `/Users/hua/Documents/Codex/IT-Code/remote/monitor-hub-history-rewrite-20261021.git`
- Test: `tests/security/history-remediation.bats`

**Interfaces:**
- Consumes: Task 1 的 rewrite mirror 和旧路径 `vmware/config.yml`。
- Produces: 不含旧路径的重写 refs，以及未受影响路径对比报告。

- [ ] **Step 1: 在 rewrite mirror 上确认测试先失败**

Run: `.tools/bats/bin/bats tests/security/history-remediation.bats`
Expected: FAIL，rewrite mirror 尚包含旧路径。

- [ ] **Step 2: 删除所有历史中的旧敏感路径**

在 rewrite mirror 中使用 `git filter-branch --index-filter` 对全部本地分支和标签删除且仅删除 `vmware/config.yml`，然后删除 `refs/original/`、过期 reflog 并执行垃圾回收。命令不得包含旧 secret 字符串。

- [ ] **Step 3: 验证重写对象库与内容**

Run: `git -C /Users/hua/Documents/Codex/IT-Code/remote/monitor-hub-history-rewrite-20261021.git fsck --full`
Expected: PASS。

Run: `.tools/bats/bin/bats tests/security/history-remediation.bats`
Expected: PASS，旧路径和敏感赋值均不可达，当前脱敏组件仍存在。

- [ ] **Step 4: 比较未受影响内容**

对 backup 与 rewrite 的最终树排除 `vmware/config.yml` 后逐路径比较 blob 内容；Expected: 所有其他路径一致，提交作者、时间和顺序保持可解释。

### Task 3: 使用 lease 更新远端并验证

**Files:**
- Modify external state: GitHub `robotneo/monitor-hub` branch and affected tags
- Preserve: 两个本地 mirror 目录

**Interfaces:**
- Consumes: `PRE_REWRITE_MAIN_SHA`、重写后的明确分支和标签清单。
- Produces: 远端不再包含旧敏感路径的 refs；本地保留可恢复备份。

- [ ] **Step 1: 强推前重新读取远端 refs**

Run: `git ls-remote --heads --tags origin`
Expected: `refs/heads/main` 仍等于 `PRE_REWRITE_MAIN_SHA`；不一致则停止并人工审计新增提交。

- [ ] **Step 2: 进行 lease 失败模拟**

使用故意错误的 expected SHA 对本地测试 remote 执行 `--force-with-lease`；Expected: 推送被拒绝，证明保护条件有效。

- [ ] **Step 3: 显式推送 main**

从 rewrite mirror 使用 `--force-with-lease=refs/heads/main:PRE_REWRITE_MAIN_SHA` 推送 `refs/heads/main:refs/heads/main`。逐个列出受影响标签并在核对旧 SHA 后显式推送；没有受影响标签时不执行标签强推。

- [ ] **Step 4: 从 GitHub 重新克隆验证**

创建全新临时克隆，运行 `git fsck --full`、工作树 secret 测试和全历史旧路径检查。

Expected: 远端 main 可正常克隆；旧 `vmware/config.yml` 不存在于可达历史；脱敏后的 `components/vmware-exporter/` 存在。

- [ ] **Step 5: 更新事件记录**

记录完成日期、重写后的 main SHA、验证命令结果和“现有克隆必须重新克隆或谨慎迁移”的通知；仍不记录任何 secret 值。

- [ ] **Step 6: 保留恢复材料并停止自动操作**

保留 backup mirror，直到用户明确同意删除。rewrite mirror 可在远端验证完成后归档，但不得自动删除。
