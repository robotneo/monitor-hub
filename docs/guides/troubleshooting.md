# 故障排查 / Troubleshooting

```bash
bin/monitorctl stack STACK doctor --mode compose --profile single-node
docker compose ps
```

- GitHub/API 超时：按错误 URL 检查网络，离线导入包或镜像后重试。
- 镜像无 digest：完整拉取镜像，或配置可信镜像仓库。
- Compose 配置失败：确认所有镜像变量是明确版本/digest，运行时路径可读。
- MySQL/Redis 不健康：检查磁盘权限、secret 权限和已有数据版本。
- Nightingale 无指标：确认 VictoriaMetrics、Categraf writer 与 heartbeat URL。
- Hybrid 重复序列：检查 `collector` 标签和采集所有权文档。
- VMware 未启动：默认即关闭；提供运行时凭据并启用 profile 后才启动。

不要通过删除数据目录来修复启动问题。先备份，再诊断和回滚。
