# vCenter 凭据历史修复记录 / vCenter credential history remediation

- 确认日期 / Confirmation date: 2026-10-22
- 状态 / Status: 历史清理进行中 / history remediation in progress
- 受影响历史路径 / Affected historical path: `vmware/config.yml`
- 处理范围 / Scope: 所有可达分支和标签中的上述旧路径，以及远端 `main` 的安全重写与复核。
- 前置确认 / Prerequisite: 管理员已确认相关 Native vCenter 密码完成更换。
- 凭据记录原则 / Credential handling: 本记录和仓库均不保存旧密码、新密码或任何凭据片段。

完成重写后，本文件将补充新的 `main` 提交 ID、验证结果和现有克隆迁移通知。

