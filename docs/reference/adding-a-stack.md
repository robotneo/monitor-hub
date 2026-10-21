# Adding a stack / 新增组合架构

每个 stack 包含 `stack.yaml`、README、profile、配置、部署文件、生命周期 hook 和
测试。`dependency_order` 必须与健康依赖一致；支撑服务与可独立使用的组件分开记录。

必须说明数据流、采集所有权、对外端口、持久数据、备份范围、secret 来源和卸载
保留策略。集群方案若没有可执行清单，只能标为文档边界，不能声明支持。

Compose 服务使用明确版本或 digest，禁止 `latest` 和默认 `privileged: true`。
数据库与缓存默认不映射到宿主机。完成后运行 schema、Compose 渲染、凭据扫描、
数据流测试和卸载保留测试。
