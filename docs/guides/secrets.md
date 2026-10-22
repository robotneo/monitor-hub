# 凭据管理 / Secrets

- 仓库只保留空值、环境变量引用或模板标记。
- 运行时 secret 位于 `/etc/monitor-hub/stacks/<stack>/secrets/`，按容器服务 UID
  设置所有权并使用只读 `0400` 权限。
- VMware 凭据只写入运行时配置，且 VMware profile 默认关闭。
- 不在 Git、工单、日志或 Compose environment 中传递明文密码。
- 轮换后执行 `restart` 与 `doctor`，记录轮换时间但不保存旧值。

首次安装 Nightingale stack 会生成 MySQL 与 Grafana secret。Nightingale 官方初始化
账号仍要求首次登录立即轮换；完成前不要暴露到不可信网络。

提交前运行 `tools/dev/scan-secrets.sh`。泄漏响应顺序是先轮换，再清理历史，最后
验证远端所有分支与标签。
