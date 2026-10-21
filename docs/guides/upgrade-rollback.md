# 升级与回滚 / Upgrade and rollback

升级前阅读 release notes、执行 `backup`、记录当前镜像 digest，并先在预生产运行
`validate` 与 `upgrade`：

```bash
bin/monitorctl stack victoriametrics-monitoring upgrade --mode compose --profile single-node
```

未指定版本时会先解析稳定版，再固定到 digest。若健康检查失败，停止新版本、
恢复备份与原 digest，然后执行 `doctor`。数据库主版本升级必须遵守上游迁移顺序，
不能依赖容器回退逆转数据格式。
