# monitor-hub

面向监控与告警基础设施的可维护部署仓库，覆盖组件发现、校验、安装、配置、
启停、升级、备份、恢复、诊断和卸载。当前实现以 Docker Compose 单节点方案为
主，同时保留 Native、Docker 与 Kubernetes 的清晰扩展边界。

A maintainable deployment repository for monitoring and alerting components,
covering validation, installation, operations, upgrades, backup/restore,
diagnostics, and uninstall. The current executable milestone focuses on
single-node Docker Compose deployments.

## 架构路线 / Stack routes

- `victoriametrics-monitoring`: Exporter → vmagent → VictoriaMetrics，Grafana 查询，vmalert → Alertmanager。
- `nightingale-monitoring`: Categraf + Nightingale + VictoriaMetrics + Grafana，MySQL/Redis 为内部支撑服务。
- `hybrid-monitoring`: Exporter/vmagent 与 Categraf 并存，通过 `collector` 标签和采集所有权避免重复采集。

每个组件也可在 `components/` 下独立维护与部署。镜像不使用可漂移标签：本地
兼容镜像优先，否则解析上游稳定版本并记录不可变 digest。离线二进制包放入
`packages/` 后优先使用。

## 快速开始 / Quick start

```bash
gmake lint
gmake validate
gmake test
bin/monitorctl stack victoriametrics-monitoring validate --mode compose --profile single-node
bin/monitorctl stack victoriametrics-monitoring install --mode compose --profile single-node
```

macOS 若系统 `make` 不可用，请使用 Homebrew GNU Make 的 `gmake`；Ubuntu/Rocky
通常可直接使用 `make`。完整说明见 [快速开始](docs/guides/quick-start.md)。

## 安全 / Security

运行时凭据只写入忽略追踪且权限受限的目录。提交前运行：

```bash
tools/dev/scan-secrets.sh
```

VMware 采集默认关闭；启用前在运行时目录创建凭据配置。问题报告和私密漏洞
报告方式见 [SECURITY.md](SECURITY.md)。

## 文档 / Documentation

- 运维指南：`docs/guides/`
- 扩展与兼容参考：`docs/reference/`
- 中英文设计规范：`docs/superpowers/specs/`
- 组件：`components/`
- 组合架构：`stacks/`
