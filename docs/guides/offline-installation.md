# 离线安装 / Offline installation

二进制安装遵循 `packages/` → 本地缓存 → 上游稳定版本的顺序。文件按组件
`versions.yaml` 中的模板命名并放到 `packages/`；校验和不匹配会立即终止。

容器镜像请在联网机器拉取明确版本，导出后导入目标主机：

```bash
docker save IMAGE:VERSION -o image.tar
docker load -i image.tar
```

`monitorctl` 先检查本地镜像，再尝试网络拉取并记录 digest。不要配置 `latest`。
Nightingale 离线资产目录由 `MH_NIGHTINGALE_ASSET_SOURCE_DIR` 指定，其中包含
`n9e.sql` 和 `config.toml`。网络不可用或 GitHub 缓慢时，错误会给出失败 URL、
所需文件和重试方式。
