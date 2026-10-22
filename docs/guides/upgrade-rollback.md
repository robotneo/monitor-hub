# 升级与回滚 / Upgrade and rollback

升级前阅读 release notes、执行 `backup`、记录当前镜像 digest，并先在预生产运行
`validate` 与 `upgrade`：

```bash
bin/monitorctl stack victoriametrics-monitoring upgrade --mode compose --profile single-node
```

未指定版本时会先解析稳定版，再固定到 digest。安装、配置、升级和恢复均使用事务阶段；
若应用或健康检查失败，会恢复变更前的配置、状态、持久数据（恢复操作）与原 digest，
然后重新启动原部署。之后执行 `doctor`。数据库主版本升级必须遵守上游迁移顺序，
不能依赖容器回退逆转数据格式。
