# Monitor Hub 仓库改造设计规范

[English](2026-10-21-monitor-hub-repository-design.md) | [中文](2026-10-21-monitor-hub-repository-design.zh-CN.md)

**状态：** 已确认；正在实施和验证
**日期：** 2026-10-21
**仓库：** `robotneo/monitor-hub`

## 1. 目标与定位

`monitor-hub` 是一个用于部署监控与告警组件、可长期维护的仓库。它必须同时支持单个组件独立部署和完整参考架构部署，并避免重复保存公共配置。

仓库面向在 Ubuntu 22.04/24.04 LTS 和 Rocky Linux 8/9 上执行部署的运维人员。最终将覆盖原生 Shell/systemd、Docker、Docker Compose 和 Kubernetes 工作流。首个实施里程碑会让三条 Docker Compose 单节点架构达到可用状态；其他部署方式只建立统一规范与扩展接口，不宣称已达到生产可用状态。

## 2. 建设目标

- 保留现有仓库名 `monitor-hub`。
- 为每个组件建立一致且可独立使用的目录和生命周期契约。
- 通过组合组件提供完整参考架构，不复制公共配置。
- 覆盖安装、配置、启动、停止、重启、状态检查、升级、备份、恢复、校验、诊断和卸载。
- 优先使用兼容的本地安装包和缓存镜像；本地不存在时，解析并下载上游最新稳定版本。
- 安装完成后记录实际解析出的二进制版本和容器镜像 digest。
- 支持安全的离线安装；网络不可用或速度过慢时提供可执行的诊断与处理指引。
- 禁止密钥进入 Git，并自动检测意外提交的凭据。
- 在 CI 中校验配置和部署产物。
- 让后续新增组件与架构的方式统一、可预测、易审计。

## 3. 首个里程碑不包含的范围

- 所有组件的生产级原生部署。
- 所有组件的生产级单容器 Docker 部署。
- 生产级 Kubernetes 部署。
- 可运行的 VictoriaMetrics 集群拓扑。
- Zabbix 部署内容。
- 尚无实际实现的空组件目录。

Kubernetes 规范在本阶段确定：成熟组件优先使用 Helm，环境差异通过 Kustomize 覆盖。集群拓扑和非 Compose 部署方式在单独实施并通过测试前，只作为有文档说明的扩展点存在。

## 4. 当前仓库问题

当前仓库规模较小，主要包含 Prometheus、Grafana、Alertmanager、PrometheusAlert、Blackbox Exporter 和 VMware Exporter 的 Docker Compose 部署配置。

迁移必须解决以下问题：

- README 仍引用旧名称 `prometheus-everything`。
- 单体 Compose 文件混合了组件配置与组合编排。
- 镜像使用可漂移的 `latest` 标签，且未记录实际部署 digest。
- 主机 IP 和 `/opt` 路径被硬编码。
- 容器通常以 root 和 privileged 方式运行，但未说明必要性。
- 缺少统一的生命周期、状态、备份、回滚、验证和兼容性契约。
- 公开 Git 历史中存在明文 vCenter 管理员凭据。
- 后续不再保留 PrometheusAlert。

## 5. 仓库结构

```text
monitor-hub/
├── bin/
│   └── monitorctl
├── lib/
│   ├── core/
│   └── adapters/
├── components/
├── stacks/
│   ├── victoriametrics-monitoring/
│   ├── nightingale-monitoring/
│   └── hybrid-monitoring/
├── packages/
│   └── README.md
├── docs/
│   ├── architecture/
│   ├── guides/
│   ├── reference/
│   └── superpowers/
├── examples/
├── schemas/
├── tests/
├── tools/
├── .github/workflows/
├── .gitignore
├── README.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── SECURITY.md
├── LICENSE
└── Makefile
```

### 5.1 目录边界

- `components/` 负责可独立部署的组件。
- `stacks/` 负责组件组合、依赖顺序、跨组件连接以及架构专属覆盖配置。
- 架构引用组件持有的配置，不保存组件默认配置的副本。
- `bin/monitorctl` 是运维人员使用的统一入口。
- `lib/` 保存可复用的生命周期逻辑和平台适配器。
- `tools/` 和 `Makefile` 面向仓库维护者。
- `packages/` 是本地安装包投放目录。二进制安装包由 Git 忽略；仓库只提交说明文档和经过明确批准的校验清单。

## 6. 组件契约

每个已经实现的组件都采用以下布局：

```text
components/<component>/
├── README.md
├── component.yaml
├── versions.yaml
├── config/
├── deploy/
│   ├── native/
│   ├── docker/
│   ├── compose/
│   └── kubernetes/
│       ├── helm/
│       └── kustomize/
├── hooks/
│   └── lifecycle.sh
└── tests/
```

`component.yaml` 声明组件类型、上游项目、依赖、端口、数据路径、健康检查、支持的操作系统、CPU 架构和部署方式。某种部署方式只有通过相应验证和冒烟测试后，才能被标记为已支持。

`versions.yaml` 描述已知的兼容版本和安装包位置。它不会强制所有新安装使用仓库固定的版本；版本解析遵循第 10 节的策略。

## 7. 架构组合契约

每个架构组合采用以下布局：

```text
stacks/<stack>/
├── README.md
├── stack.yaml
├── profiles/
│   ├── single-node/
│   └── cluster/
│       └── README.md
├── deploy/
│   └── compose/
│       ├── compose.yaml
│       ├── .env.example
│       └── config/
├── hooks/
│   └── lifecycle.sh
└── tests/
```

`stack.yaml` 是组件清单、依赖顺序、支持的 profile、支持的部署方式、所需端口、存储和健康检查的唯一事实来源。

首个里程碑仅让 `single-node` 与 Docker Compose 组合达到可用状态。`cluster/README.md` 只定义未来的拓扑和前置条件，不提供未经验证的部署清单。

## 8. 参考架构

### 8.1 `victoriametrics-monitoring`

- 各类 Exporter
- vmagent
- VictoriaMetrics 单节点版
- Grafana
- vmalert
- Alertmanager

Exporter 向 vmagent 提供指标，vmagent 将指标写入 VictoriaMetrics，Grafana 查询 VictoriaMetrics，vmalert 基于 VictoriaMetrics 计算告警规则并将通知发送给 Alertmanager。

### 8.2 `nightingale-monitoring`

- Categraf
- Nightingale
- VictoriaMetrics 单节点版
- Grafana

Categraf 负责采集指标，VictoriaMetrics 负责存储，Nightingale 提供监控和告警工作流，Grafana 提供可视化。

### 8.3 `hybrid-monitoring`

- 各类 Exporter
- vmagent
- Categraf
- Nightingale
- VictoriaMetrics 单节点版
- Grafana

这条路线面向 Prometheus 兼容 Exporter 与 Categraf 并存的环境。采集链路必须使用明确的标签和任务命名，以便识别并避免重复时序数据。

## 9. 用户接口与生命周期

示例：

```bash
monitorctl component prometheus install --mode native
monitorctl component vmware-exporter status --mode docker
monitorctl stack victoriametrics-monitoring install --mode compose --profile single-node
```

统一生命周期动作：

```text
install configure start stop restart status
upgrade backup restore uninstall validate doctor
```

通用选项包括 `--version`、`--dry-run`、`--yes` 和 `--purge-data`。组件的
`--version` 接受一个明确版本；stack 使用逗号分隔的 `component=version` 映射，
避免把同一版本错误套用到不同组件。删除数据必须明确传入 `--purge-data`；
`--yes` 只用于关闭交互确认，并不代表允许删除数据。

每次会修改系统的操作按以下事务流程执行：

1. 检测操作系统、版本、软件包管理器、初始化系统和 CPU 架构。
2. 校验权限、端口、存储、依赖和网络前置条件。
3. 解析兼容的安装产物。
4. 在具备校验信息时检查文件校验和与容器元数据。
5. 对可能替换数据或配置的操作，先备份现有部署。
6. 在临时目录中渲染配置。
7. 执行语法和语义校验。
8. 应用变更。
9. 执行健康检查。
10. 保存实际安装版本、容器 digest、配置指纹和操作结果。

如果验证失败，不应用任何变更。如果应用或健康检查失败，命令会保留诊断日志；当旧状态已知且回滚安全时自动恢复，否则停止并给出明确的人工恢复步骤。

## 10. 安装包与版本策略

安装产物按以下优先级选择：

1. 用户明确指定的兼容版本或本地安装包。
2. `packages/` 或运行时缓存中已有的兼容安装包。
3. 在线解析得到的上游最新稳定版本，排除 alpha、beta 和 release candidate 等预发布版本。

在线安装时，`monitorctl` 会在下载前将当前稳定版本解析为明确版本号。容器镜像拉取后按不可变 digest 记录。因此，即使初次选择策略是“最新稳定版”，最终部署状态仍然可以复现。

下载失败或速度过慢时，命令必须显示：

- 尝试访问的来源和失败原因；
- 所需文件名、明确版本、操作系统和 CPU 架构；
- 文件应放置的本地目录；
- 已知情况下的预期校验和；
- 支持的代理、GitHub 镜像和容器镜像源配置方法；
- 可以直接重试的完整命令。

系统不会自动选择不受信任的镜像源。

## 11. 主机文件系统契约

```text
/etc/monitor-hub/          渲染后的配置和非敏感设置
/var/lib/monitor-hub/      部署状态和组件数据引用
/var/cache/monitor-hub/    已下载的安装包和缓存元数据
/var/log/monitor-hub/      命令与组件部署日志
/var/backups/monitor-hub/  带时间戳的备份和恢复元数据
```

Secret 文件必须使用严格权限并位于 Git 之外。文件所有权和服务用户由组件分别定义；除非某项能力确实需要并有文档说明，否则不使用 root 用户或 privileged 容器。

## 12. 安全与 Secret 管理

- 真实 secret 不得存入已提交的配置或示例。
- `.env.example` 和示例 YAML 只能包含占位值。
- Secret 通过受保护的环境文件、挂载的 secret 文件、适用时的 Docker secrets，以及未来 Kubernetes 工作中的 Kubernetes Secrets 或外部 secret provider 注入。
- 日志必须对已知敏感字段的值进行脱敏。
- CI 扫描新增提交中的疑似凭据。
- VMware 配置改为脱敏模板；已暴露凭据绝不能复制到新目录。
- 重写仓库历史前，运维人员必须先更换已暴露的 vCenter 凭据。

### 12.1 Git 历史修复

历史修复属于已批准的项目范围，但仍是一项需要单独确认的破坏性操作：

1. 确认已暴露的 vCenter 凭据已更换。
2. 创建并验证可恢复的镜像备份，记录所有远端引用。
3. 重写所有受影响引用，清除包含 secret 的文件内容。
4. 验证被移除的值和敏感模式不再存在于重写后的历史中。
5. 使用明确的引用目标强制推送重写后的分支和标签。
6. 记录已有克隆需要废弃重拉，或谨慎地重新基于已重写历史进行同步。

在确认密码已经更换并完成最后一次推送前审计之前，不执行历史重写或强制推送。

## 13. 迁移映射

- 现有 Prometheus 配置迁移到 `components/prometheus/` 并参数化。
- 现有 Alertmanager 配置迁移到 `components/alertmanager/`；删除 PrometheusAlert 路由，改为安全示例。
- 现有 Compose 中的 Grafana 内容改为不包含内置凭据的组件定义。
- 现有 Blackbox Exporter 配置迁移到 `components/blackbox-exporter/`。
- 现有 VMware Exporter 配置迁移到 `components/vmware-exporter/`，并改为脱敏模板。
- 现有单体 Compose 文件由组件定义和三条已确认架构替代。
- 删除 `alert/` 及全部 PrometheusAlert 配置。
- 不创建或保留 `prometheus-vmware` 架构。
- 原有硬编码主机地址和路径改为有文档说明的变量，并尽可能提供安全默认值。

## 14. 验证与 CI

验证体系包括：

- Shell 语法、格式和静态检查。
- YAML 校验，以及 `component.yaml` 和 `stack.yaml` 的 Schema 校验。
- Docker Compose 渲染与依赖检查。
- 在官方工具支持的情况下，执行 Prometheus 和 Alertmanager 配置校验。
- Secret 扫描。
- 生命周期分发、平台检测、版本选择、dry-run 行为以及危险操作保护的单元测试。
- 三条单节点 Compose 架构的轻量冒烟测试。
- 在可行的情况下，使用一次性测试环境检查 Ubuntu 22.04/24.04 和 Rocky Linux 8/9 兼容性。
- 对框架示例执行 Helm template、Kustomize build 和 Kubernetes Schema 渲染检查，但不宣称其已具备生产支持。

维护者统一入口：

```bash
make lint
make validate
make test
make smoke
```

## 15. 文档

仓库提供以下文档：

- 每条可用架构的快速开始。
- 组件级部署和生命周期操作说明。
- 兼容性与支持矩阵。
- 离线安装和镜像源配置。
- 备份与恢复流程。
- 升级与回滚流程。
- Secret 管理。
- 新增组件指南。
- 新增架构指南。
- 故障排查与诊断信息收集。
- 旧目录结构迁移指南。

每个组件和架构的 README 都要标注各部署方式的成熟度：规划中、实验性、已测试或生产可用。

## 16. 首个里程碑验收标准

- 仓库名称保持为 `monitor-hub`。
- 不存在 PrometheusAlert 和此前讨论过的 `prometheus-vmware` 架构。
- 原有需要保留的组件已迁移到统一组件契约中，且不包含已提交的真实凭据。
- 三条已确认架构都具有可用且经过验证的 Docker Compose 单节点 profile。
- 集群 profile 只包含说明文档，且不能被作为已支持的部署方式调用。
- `monitorctl` 实现带安全保护的完整生命周期接口；尚未支持的动作必须清楚报错，不能假装成功。
- 优先使用兼容的本地安装包，再考虑网络下载。
- 在线安装会把最新稳定版解析为可记录的明确版本和 digest。
- 网络失败时提供可执行的离线处理说明。
- Ubuntu 22.04/24.04 和 Rocky Linux 8/9 均纳入兼容性验证。
- CI 校验 Shell、YAML、Compose、组件配置、secret 和生命周期行为。
- 凭据历史重写在密码更换和破坏性操作最终审计前保持阻塞。

## 17. 实施拆分

实施计划应拆分为可以独立审计的工作流：

1. 当前工作树中的安全整改和仓库防护。
2. 元数据 Schema、公共目录骨架和文档规范。
3. `monitorctl`、公共生命周期库、平台适配器、状态管理、安装包解析和安全保护。
4. 迁移现有需要保留的组件。
5. 新增 VictoriaMetrics、vmagent、vmalert、Nightingale 和 Categraf 组件定义。
6. 三条 Docker Compose 单节点架构。
7. 验证、冒烟测试、CI 和运维文档。
8. 凭据更换后，单独设闸执行 Git 历史重写。

每个工作流都必须产生可测试的提交，且不得把未经验证的部署方式标记为已支持。
