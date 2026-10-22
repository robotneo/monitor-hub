# Hybrid monitoring stack

Categraf owns host metrics. vmagent owns exporter scraping. Both write to
VictoriaMetrics with distinct `collector` labels; Nightingale handles alerting
and Grafana handles visualization. VMware collection is disabled by default.

```bash
bin/monitorctl stack hybrid-monitoring install --mode compose --profile single-node
```

首次登录 Nightingale 后必须立即轮换官方初始化的默认 root 密码。MySQL 与
Grafana 使用按服务 UID 限制为只读 `0400` 的文件型 secret。

Read `config/collection-ownership.md` before enabling any overlapping input.
Uninstall preserves MySQL and VictoriaMetrics data unless purge is explicit.
