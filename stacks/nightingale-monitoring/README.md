# Nightingale monitoring stack

Categraf writes metrics to VictoriaMetrics and sends heartbeat metadata to
Nightingale. Nightingale and Grafana query VictoriaMetrics. MySQL and Redis are
internal-only supporting services.

```bash
bin/monitorctl stack nightingale-monitoring install --mode compose --profile single-node
```

首次安装会生成 MySQL 与 Grafana secret，并按对应容器 UID 设置只读 `0400`
权限。Nightingale 官方初始化数据仍会创建默认 `root` 账号；首次登录后必须立即
设置新密码。不要把运行时 secret 文件提交到仓库。

安装流程会为解析出的 Nightingale 精确版本准备 `n9e.sql`，记录 SHA-256，并把它
只读挂载到 MySQL 的首次初始化目录。已有数据库不会重复执行初始化 SQL。

Images are resolved to immutable digests. MySQL uses the verified 8.4.8 LTS
baseline and Redis uses 8.6.7-alpine; both are converted to local digests before
deployment. `uninstall` preserves data unless `--purge-data --yes` is explicit.
