# 备份与恢复 / Backup and restore

```bash
bin/monitorctl stack hybrid-monitoring backup --mode compose --profile single-node
```

备份包含配置、持久数据、源路径清单和 SHA-256 校验文件。默认写入
`/var/backups/monitor-hub`，可用 `MH_BACKUP_DIR` 改到加密存储。

恢复前停止服务并验证 `checksums.sha256`：

```bash
export MH_RESTORE_PATH=/var/backups/monitor-hub/stack/hybrid-monitoring/TIMESTAMP
bin/monitorctl stack hybrid-monitoring restore --mode compose --profile single-node
```

恢复会替换清单中的目标路径。恢复后运行 `doctor` 并验证查询、写入和告警链路。
