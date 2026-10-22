# vCenter 凭据历史修复记录 / vCenter credential history remediation

- 确认日期 / Confirmation date: 2026-10-22
- 状态 / Status: 已完成 / completed
- 受影响历史路径 / Affected historical path: `vmware/config.yml`
- 处理范围 / Scope: 所有可达分支和标签中的上述旧路径，以及远端 `main` 的安全重写与复核。
- 前置确认 / Prerequisite: 管理员已确认相关 Native vCenter 密码完成更换。
- 凭据记录原则 / Credential handling: 本记录和仓库均不保存旧密码、新密码或任何凭据片段。

## 完成记录 / Completion record

- 完成日期 / Completion date: 2026-10-22
- 重写后的 `main` 基线 / Rewritten `main` baseline: `d18dbba73fe93a85135d27946212e2a892adf820`
- 验证结果 / Verification: backup 与 rewrite mirror 均通过 `git fsck --full`；
  4 项历史清理测试全部通过；从 GitHub 全新克隆后再次通过对象检查、工作树
  secret 扫描和全历史旧路径检查。
- 克隆迁移通知 / Clone migration notice: 现有克隆不得直接继续推送旧提交链；应重新克隆，
  或在明确备份本地工作后谨慎迁移到重写后的 `main`。

