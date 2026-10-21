# 旧目录迁移 / Migration from legacy layout

旧的顶层 Prometheus、Alertmanager、Blackbox、VMware 与单体 Compose 文件已迁移到
`components/`；组合部署迁移到 `stacks/`。旧的 PrometheusAlert 和
`prometheus-vmware` 组合不再保留。

迁移时先备份；将自定义规则合并到对应组件或 stack；把 VMware 凭据移到运行时
文件；执行 `validate`；使用并行测试端口比较采集、查询与告警；最后停止旧部署。
不要直接覆盖旧数据卷。

Legacy `/opt/...` paths are replaced by `MH_CONFIG_DIR` and `MH_DATA_DIR`.
Webhook and notification settings must be reintroduced into protected runtime
configuration.
