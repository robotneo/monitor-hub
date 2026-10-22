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
bin/monitorctl component victoriametrics validate --mode compose --version 1.129.0
```

组件的 `--version` 接受一个明确版本。stack 中的组件版本彼此独立，使用逗号分隔的
`component=version` 映射；未列出的组件解析其最新稳定版。外部支撑镜像通过对应的
`*_IMAGE` 环境变量传入明确 tag 或 digest。

```bash
bin/monitorctl stack victoriametrics-monitoring upgrade --mode compose \
  --profile single-node \
  --version 'victoriametrics=1.129.0,grafana=12.2.0,vmagent=1.129.0'
```

只有元数据声明的模式可以执行。当前 stack 的 `cluster` 目录只记录设计边界。
