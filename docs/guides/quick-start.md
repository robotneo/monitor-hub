# 快速开始 / Quick start

前置条件：受支持 Linux、Bash、Git、curl、OpenSSL、Docker Engine 与 Docker
Compose plugin；部署账号需能写标准运行目录。

```bash
make lint
make validate
make test
bin/monitorctl stack nightingale-monitoring validate --mode compose --profile single-node
bin/monitorctl stack nightingale-monitoring install --mode compose --profile single-node
bin/monitorctl stack nightingale-monitoring doctor --mode compose --profile single-node
```

生命周期动作统一为 `install configure start stop restart status upgrade backup
restore uninstall validate doctor`。卸载默认保留数据；永久删除必须显式添加
`--purge-data --yes`。

单个组件使用相同命令形式，但不需要 `--profile`：

```bash
bin/monitorctl component victoriametrics validate --mode compose
```

只有元数据声明的模式可以执行。当前 stack 的 `cluster` 目录只记录设计边界。
