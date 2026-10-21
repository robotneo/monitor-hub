# Nightingale monitoring stack

Categraf writes metrics to VictoriaMetrics and sends heartbeat metadata to
Nightingale. Nightingale and Grafana query VictoriaMetrics. MySQL and Redis are
internal-only supporting services.

```bash
bin/monitorctl stack nightingale-monitoring install --mode compose --profile single-node
```

首次安装会生成 MySQL、Grafana 以及 Nightingale 初始密码候选文件，权限为
`0600`。Nightingale 官方初始化数据仍会创建默认 `root` 账号；首次登录后必须
立即使用生成的候选密码完成轮换。不要把运行时 secret 文件提交到仓库。

Images are resolved to immutable digests. MySQL uses the verified 8.4.8 LTS
baseline and Redis uses 8.6.7-alpine; both are converted to local digests before
deployment. `uninstall` preserves data unless `--purge-data --yes` is explicit.
