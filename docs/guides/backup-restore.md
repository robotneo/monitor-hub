# 备份与恢复 / Backup and restore

```bash
bin/monitorctl stack hybrid-monitoring backup --mode compose --profile single-node
```

备份包含配置、持久数据、源路径清单和 SHA-256 校验文件。默认写入
`/var/backups/monitor-hub`，可用 `MH_BACKUP_DIR` 改到加密存储。

恢复前会先验证 `checksums.sha256`、清单路径和载荷类型；只有全部通过后才停止服务。
恢复操作还会自动创建恢复前快照，并纳入与安装、配置、升级相同的事务边界：

```bash
export MH_RESTORE_PATH=/var/backups/monitor-hub/stack/hybrid-monitoring/TIMESTAMP
bin/monitorctl stack hybrid-monitoring restore --mode compose --profile single-node
```

恢复会替换清单中的目标路径，并在服务通过健康检查后写入新状态。如果应用或健康检查失败，
系统会恢复原配置、持久数据和镜像 digest，再重新启动原部署。恢复成功后仍应运行
`doctor`，并验证查询、写入和告警链路。
