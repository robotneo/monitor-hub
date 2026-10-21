# Monitor Hub 首个里程碑实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将现有仓库改造成具备统一组件契约、完整生命周期入口和三条可用 Docker Compose 单节点监控架构的 `monitor-hub`。

**Architecture:** 以 `components/` 保存可独立复用的组件定义，以 `stacks/` 保存组合关系和架构专属覆盖配置。`bin/monitorctl` 通过 Shell 公共库完成平台检测、安装包解析、状态记录、安全事务和生命周期分发；首个里程碑只把 Docker Compose 单节点模式标记为可用。

**Tech Stack:** Bash 4.4+、Bats Core、Docker Engine、Docker Compose v2、YAML/JSON Schema、ShellCheck、shfmt、yamllint、GitHub Actions。

**Spec:** `docs/superpowers/specs/2026-10-21-monitor-hub-repository-design.zh-CN.md`（中文）与 `docs/superpowers/specs/2026-10-21-monitor-hub-repository-design.md`（English）

## Global Constraints

- 仓库名称保持为 `monitor-hub`。
- 支持基线为 Ubuntu 22.04/24.04 LTS 与 Rocky Linux 8/9，CPU 架构至少识别 `amd64` 和 `arm64`。
- 首个里程碑仅把 Docker Compose `single-node` profile 标记为可用；native、单容器 Docker、Kubernetes 和 VictoriaMetrics cluster 不得宣称生产可用。
- PrometheusAlert 及 `prometheus-vmware` 架构必须移除。
- 不得提交真实 secret、运行时 `.env`、生成的 secret 文件或 `packages/` 中的二进制文件。
- 本地兼容安装包或已有镜像优先；否则解析上游最新兼容稳定版本，并记录确切版本与镜像 digest。
- 所有危险操作支持 `--dry-run`；删除数据必须显式使用 `--purge-data`。
- 新增组件或 stack 必须通过 Schema、配置渲染和对应成熟度级别的测试后才能标记为支持。
- Nightingale 的 MySQL 与 Redis 属于 Compose 架构内部支撑服务，不单独扩展本里程碑的组件范围。

## Review Focus

- 不受支持的组件名、stack 名或包含 `../` 的输入必须在访问文件系统前被拒绝；由 Task 5 的 CLI 测试固定。
- 本地安装包架构不匹配、校验和错误或下载中断时不得修改当前部署；由 Task 4 的安装包解析测试固定。
- 升级过程中配置校验或健康检查失败时必须保留诊断信息并恢复旧状态；由 Task 5 的事务测试固定。
- secret 不得出现在生成配置、日志或 Git 跟踪文件中；由 Task 1 与 Task 10 的安全测试固定。
- vmagent 与 Categraf 同时存在时不得无提示地产生重复时序；由 Task 9 的 hybrid 配置测试固定。

---

## 参考资料

- VictoriaMetrics 官方 Compose 架构：`https://github.com/VictoriaMetrics/VictoriaMetrics/tree/master/deployment/docker`
- Nightingale 官方 Compose：`https://github.com/ccfos/nightingale/tree/main/docker/compose-bridge`
- Categraf 官方仓库：`https://github.com/flashcatcloud/categraf`

### Task 1: 工作树安全整改与测试工具基线

**Files:**
- Create: `.gitignore`
- Create: `.gitleaks.toml`
- Create: `tools/dev/bootstrap-test-tools.sh`
- Create: `tests/security/no-secrets.bats`
- Create: `tests/security/ignored-runtime-files.bats`
- Modify: `vmware/config.yml`
- Modify: `alertmanager/alertmanager.yml`
- Delete: `alert/app.conf`

**Interfaces:**
- Consumes: 当前仓库中的公开配置。
- Produces: 可重复安装的测试工具目录 `.tools/`，以及无真实凭据的安全工作树；后续任务默认以此为基线。

- [ ] **Step 1: 固定测试工具并编写失败的 secret 与忽略规则测试**

`tools/dev/bootstrap-test-tools.sh` 将 Bats Core 安装到 Git 忽略的 `.tools/`，并从脚本内的明确版本常量读取版本号。在 `tests/security/no-secrets.bats` 中断言所有 Git 跟踪文件不包含已赋值的 `vsphere_password`、Webhook token、默认生产密码或私钥头；在 `tests/security/ignored-runtime-files.bats` 中断言 `.env`、`secrets/`、`.tools/`、`packages/**` 二进制和生成状态文件被 Git 忽略。

- [ ] **Step 2: 安装并运行 Bats，确认测试失败**

Run: `bash tools/dev/bootstrap-test-tools.sh && .tools/bats/bin/bats tests/security`
Expected: FAIL，指出现有 vCenter 明文凭据、PrometheusAlert 配置以及缺失的忽略规则。

- [ ] **Step 3: 完成最小安全整改**

将 `vmware/config.yml` 的主机、用户名和密码改为变量占位；将 Alertmanager 的 PrometheusAlert webhook 改为禁用的安全示例；删除 `alert/app.conf`。`.gitignore` 必须覆盖真实 secret、运行时文件、测试工具和离线二进制，`.gitleaks.toml` 只允许明确的示例占位值。

- [ ] **Step 4: 重新运行安全测试**

Run: `.tools/bats/bin/bats tests/security && git diff --check`
Expected: PASS；无空白错误。

- [ ] **Step 5: 提交安全基线**

```bash
git add .gitignore .gitleaks.toml tools/dev tests/security vmware/config.yml alertmanager/alertmanager.yml alert/app.conf
git commit -m "security: remove committed monitoring credentials"
```

### Task 2: 元数据 Schema 与仓库骨架

**Files:**
- Create: `schemas/component.schema.json`
- Create: `schemas/stack.schema.json`
- Create: `schemas/versions.schema.json`
- Create: `packages/README.md`
- Create: `docs/reference/component-contract.md`
- Create: `docs/reference/stack-contract.md`
- Create: `docs/reference/support-levels.md`
- Create: `tests/schema/fixtures/valid-component.yaml`
- Create: `tests/schema/fixtures/invalid-component.yaml`
- Create: `tests/schema/fixtures/valid-stack.yaml`
- Create: `tests/schema/fixtures/invalid-stack.yaml`
- Create: `tests/schema/metadata.bats`
- Create: `Makefile`

**Interfaces:**
- Consumes: 设计规范中的组件和 stack 契约。
- Produces: `component.yaml`、`stack.yaml`、`versions.yaml` 的稳定字段定义，以及 `make validate` 入口。

- [ ] **Step 1: 编写 Schema 失败测试**

测试必须断言合法 fixture 通过、缺少 `name`/`kind`/`support` 的 fixture 失败、未知部署模式失败、stack 引用不存在 profile 时失败。

- [ ] **Step 2: 运行测试并确认失败**

Run: `.tools/bats/bin/bats tests/schema/metadata.bats`
Expected: FAIL，原因是 Schema 和验证入口尚不存在。

- [ ] **Step 3: 实现三个 Schema 与契约文档**

`component.schema.json` 固定字段 `name`、`kind`、`upstream`、`ports`、`paths`、`platforms`、`architectures`、`modes`、`healthcheck`；`stack.schema.json` 固定字段 `name`、`components`、`supporting_services`、`dependency_order`、`profiles`、`modes`；`versions.schema.json` 固定 `release_source`、`repository`、`tag_transform`、`artifacts`、`images` 和 `compatibility`。

- [ ] **Step 4: 增加维护入口并验证**

`Makefile` 的 `validate-schema` 目标调用固定版本的 JSON Schema 校验工具；`make validate` 先包含该目标。

Run: `make validate-schema`
Expected: PASS，两个合法 fixture 通过，两个非法 fixture 被测试确认拒绝。

- [ ] **Step 5: 提交 Schema 与骨架**

```bash
git add schemas packages docs/reference tests/schema Makefile
git commit -m "feat: define component and stack contracts"
```

### Task 3: 平台检测、路径与日志公共库

**Files:**
- Create: `lib/core/constants.sh`
- Create: `lib/core/log.sh`
- Create: `lib/core/platform.sh`
- Create: `lib/core/paths.sh`
- Create: `tests/unit/log.bats`
- Create: `tests/unit/platform.bats`
- Create: `tests/unit/paths.bats`

**Interfaces:**
- Consumes: 环境变量 `MH_ROOT_DIR`、`MH_LOG_LEVEL`，以及 `/etc/os-release`。
- Produces: `mh_log LEVEL MESSAGE`；`mh_detect_platform OS_RELEASE_PATH`，导出 `MH_OS_ID`、`MH_OS_VERSION_ID`、`MH_ARCH`、`MH_INIT_SYSTEM`；`mh_init_paths`，导出配置、状态、缓存、日志和备份路径。

- [ ] **Step 1: 编写平台矩阵和路径失败测试**

为 Ubuntu 22.04、Ubuntu 24.04、Rocky 8、Rocky 9、未知发行版、`x86_64` 和 `aarch64` fixture 编写断言；路径测试使用临时 `MH_ROOT_DIR`，不得写入真实 `/etc` 或 `/var`。

- [ ] **Step 2: 运行单元测试并确认失败**

Run: `.tools/bats/bin/bats tests/unit/log.bats tests/unit/platform.bats tests/unit/paths.bats`
Expected: FAIL，公共函数尚不存在。

- [ ] **Step 3: 实现公共函数**

`mh_detect_platform` 只接受明确支持的 OS/版本并把 `x86_64` 映射为 `amd64`、`aarch64` 映射为 `arm64`；`mh_init_paths` 在测试根目录与真实根目录之间使用同一套相对路径；日志函数必须把已注册的 secret 值替换为 `[REDACTED]`。

- [ ] **Step 4: 运行单元测试和 Shell 静态检查**

Run: `.tools/bats/bin/bats tests/unit/log.bats tests/unit/platform.bats tests/unit/paths.bats && shellcheck lib/core/*.sh`
Expected: PASS。

- [ ] **Step 5: 提交公共运行时**

```bash
git add lib/core tests/unit
git commit -m "feat: add platform and runtime path detection"
```

### Task 4: 安装包、镜像与部署状态解析

**Files:**
- Create: `lib/core/artifacts.sh`
- Create: `lib/core/state.sh`
- Create: `lib/adapters/github-releases.sh`
- Create: `lib/adapters/container-images.sh`
- Create: `tests/unit/artifacts.bats`
- Create: `tests/unit/state.bats`
- Create: `tests/fixtures/releases/`

**Interfaces:**
- Consumes: `versions.yaml`、`packages/`、运行时缓存、GitHub Releases 响应和本地容器镜像列表。
- Produces: `mh_resolve_artifact COMPONENT REQUESTED_VERSION OS ARCH`，导出 `MH_ARTIFACT_VERSION`、`MH_ARTIFACT_PATH`、`MH_ARTIFACT_SOURCE`、`MH_ARTIFACT_SHA256`；`mh_resolve_image COMPONENT REQUESTED_VERSION`，导出 `MH_IMAGE_REFERENCE` 与 `MH_IMAGE_DIGEST`；`mh_state_read KIND NAME` 与 `mh_state_write KIND NAME JSON_FILE`。

- [ ] **Step 1: 编写解析顺序和失败模式测试**

测试本地明确版本、本地自动匹配、缓存命中、在线最新稳定版、预发布排除、错误 CPU 架构、错误 SHA256、GitHub 限流、网络超时和本地镜像命中。失败测试必须断言没有状态文件被写入。

- [ ] **Step 2: 运行测试并确认失败**

Run: `.tools/bats/bin/bats tests/unit/artifacts.bats tests/unit/state.bats`
Expected: FAIL，解析器和尚未定义的状态接口缺失。

- [ ] **Step 3: 实现本地优先解析和精确版本记录**

GitHub 适配器从 fixture 或 API 解析最新兼容稳定 tag；`tag_transform` 处理镜像 tag 与 release tag 差异；容器适配器优先匹配本地镜像，否则拉取明确 tag，并通过 `docker image inspect` 记录 digest。网络错误输出 URL、目标文件名、放置目录、校验和和重试命令。

- [ ] **Step 4: 验证解析器**

Run: `.tools/bats/bin/bats tests/unit/artifacts.bats tests/unit/state.bats && shellcheck lib/core/artifacts.sh lib/core/state.sh lib/adapters/*.sh`
Expected: PASS。

- [ ] **Step 5: 提交安装包解析器**

```bash
git add lib/core/artifacts.sh lib/core/state.sh lib/adapters tests/unit tests/fixtures/releases
git commit -m "feat: add offline-first artifact resolution"
```

### Task 5: `monitorctl`、生命周期分发与安全事务

**Files:**
- Create: `bin/monitorctl`
- Create: `lib/core/args.sh`
- Create: `lib/core/dispatch.sh`
- Create: `lib/core/transaction.sh`
- Create: `lib/core/backup.sh`
- Create: `lib/adapters/compose.sh`
- Create: `tests/cli/monitorctl.bats`
- Create: `tests/unit/transaction.bats`
- Create: `tests/unit/backup.bats`

**Interfaces:**
- Consumes: `monitorctl <component|stack> <name> <action> --mode MODE [--profile PROFILE] [--version VERSION] [--dry-run] [--yes] [--purge-data]`。
- Produces: `mh_dispatch KIND NAME ACTION MODE PROFILE`；组件 hook `component_lifecycle ACTION MODE PROFILE`；stack hook `stack_lifecycle ACTION MODE PROFILE`；事务函数 `mh_transaction_begin`、`mh_transaction_commit`、`mh_transaction_rollback`。

- [ ] **Step 1: 编写 CLI、路径穿越和危险操作失败测试**

覆盖帮助文本、未知动作、未知模式、缺少 profile、`../` 名称、绝对路径名称、`--dry-run` 无写入、`--yes` 不隐含 purge、无 `--purge-data` 时保留数据。

- [ ] **Step 2: 编写事务与备份失败测试**

断言配置校验失败时不进入 apply；健康检查失败时恢复旧配置和状态；首次安装失败且无旧状态时输出人工恢复步骤；备份目录包含 manifest 和校验和。

- [ ] **Step 3: 运行测试并确认失败**

Run: `.tools/bats/bin/bats tests/cli tests/unit/transaction.bats tests/unit/backup.bats`
Expected: FAIL，入口和事务函数尚不存在。

- [ ] **Step 4: 实现 CLI 与事务边界**

CLI 只允许 Schema 中列出的 kind、action、mode 和 profile；分发前将名称限制为 `[a-z0-9][a-z0-9-]*`。修改动作按 preflight、resolve、backup、render、validate、apply、health、state 顺序执行；Compose 适配器统一设置 `--project-directory` 和多个 `-f` 片段。

- [ ] **Step 5: 验证 CLI 与事务**

Run: `.tools/bats/bin/bats tests/cli tests/unit/transaction.bats tests/unit/backup.bats && shellcheck bin/monitorctl lib/core/*.sh lib/adapters/*.sh`
Expected: PASS。

- [ ] **Step 6: 提交生命周期框架**

```bash
git add bin lib tests/cli tests/unit Makefile
git commit -m "feat: add safe monitor lifecycle controller"
```

### Task 6: 迁移现有保留组件

**Files:**
- Create: `components/prometheus/`
- Create: `components/alertmanager/`
- Create: `components/grafana/`
- Create: `components/blackbox-exporter/`
- Create: `components/vmware-exporter/`
- Create: `tests/components/retained-components.bats`
- Delete: `prometheus/`
- Delete: `alertmanager/`
- Delete: `blackbox/`
- Delete: `vmware/`
- Delete: `compose/`

**Interfaces:**
- Consumes: Task 2 的元数据契约和 Task 5 的 `component_lifecycle` hook。
- Produces: 五个符合契约的组件；每个组件提供 `component.yaml`、`versions.yaml`、README、脱敏配置、Compose 片段、生命周期 hook 和验证命令。

- [ ] **Step 1: 编写迁移失败测试**

断言五个组件通过 Schema；旧目录不存在；Prometheus 地址、VMware 连接和 Alertmanager receiver 均为变量或 secret 文件；Compose 片段不使用 `latest`、不使用不必要的 `privileged`、不内置主机 IP。

- [ ] **Step 2: 运行测试并确认失败**

Run: `.tools/bats/bin/bats tests/components/retained-components.bats`
Expected: FAIL，组件目录尚未创建。

- [ ] **Step 3: 迁移配置和元数据**

使用 `git mv` 保留可追踪历史；Prometheus 配置改为模板，Grafana 配置数据源 provisioning，Blackbox 保留模块但移除环境专属目标，VMware 使用只读 secret 文件或环境变量。每个 `versions.yaml` 定义官方 release/image 来源和兼容 tag 转换。

- [ ] **Step 4: 实现组件 Compose 片段与 hook**

Compose 片段引用 `${MH_CONFIG_DIR}`、`${MH_DATA_DIR}` 和解析后的 `${*_IMAGE}`；组件 hook 至少可靠实现 `validate`、`install`、`start`、`stop`、`restart`、`status`、`backup`、`restore`、`upgrade` 和 `uninstall` 的 Compose 路径，未支持模式清楚返回 unsupported。

- [ ] **Step 5: 验证迁移**

Run: `make validate && .tools/bats/bin/bats tests/components/retained-components.bats`
Expected: PASS；`git grep -nE '(172\.17\.|vsphere_password:[[:space:]]+[^$<])' -- components stacks` 无匹配。

- [ ] **Step 6: 提交组件迁移**

```bash
git add components tests/components prometheus alertmanager blackbox vmware compose
git commit -m "refactor: migrate existing monitoring components"
```

### Task 7: 新增 VictoriaMetrics、vmagent、vmalert、Nightingale 与 Categraf

**Files:**
- Create: `components/victoriametrics/`
- Create: `components/vmagent/`
- Create: `components/vmalert/`
- Create: `components/nightingale/`
- Create: `components/categraf/`
- Create: `tests/components/new-components.bats`

**Interfaces:**
- Consumes: 组件 Schema、安装包解析接口和 Compose component hook。
- Produces: 五个可由 stack 组合的组件片段；VictoriaMetrics 写入 `/api/v1/write`，vmagent 使用 Prometheus scrape 配置，vmalert 通过 notifier URL 连接 Alertmanager，Nightingale 使用外部 MySQL/Redis/VictoriaMetrics，Categraf 使用明确的 writer 配置。

- [ ] **Step 1: 编写组件契约与连接测试**

断言元数据通过 Schema、服务端口与健康检查存在、配置不包含固定凭据、Nightingale 不暴露 MySQL/Redis 到宿主机、Categraf 的 host mount 只在启用主机采集 profile 时出现。

- [ ] **Step 2: 运行测试并确认失败**

Run: `.tools/bats/bin/bats tests/components/new-components.bats`
Expected: FAIL，新组件尚不存在。

- [ ] **Step 3: 实现组件元数据、配置与 Compose 片段**

以官方 VictoriaMetrics Docker 部署和 Nightingale `compose-bridge` 为配置基线；去除官方示例中的默认密码、`latest` 漂移和无条件宿主机端口暴露。Nightingale release 资产准备函数按已解析版本获取对应初始化 SQL 和默认配置，再应用仓库维护的安全覆盖。

- [ ] **Step 4: 实现生命周期 hook 和配置校验**

VictoriaMetrics 系列使用官方 `-dryRun` 或对应配置检查能力；Nightingale/Categraf 使用容器内配置解析或启动前最小验证。所有 hook 遵循 Task 5 的同一签名。

- [ ] **Step 5: 验证并提交**

Run: `make validate && .tools/bats/bin/bats tests/components/new-components.bats`
Expected: PASS。

```bash
git add components tests/components
git commit -m "feat: add VictoriaMetrics and Nightingale components"
```

### Task 8: `victoriametrics-monitoring` 单节点 Compose 架构

**Files:**
- Create: `stacks/victoriametrics-monitoring/README.md`
- Create: `stacks/victoriametrics-monitoring/stack.yaml`
- Create: `stacks/victoriametrics-monitoring/profiles/single-node/profile.yaml`
- Create: `stacks/victoriametrics-monitoring/profiles/cluster/README.md`
- Create: `stacks/victoriametrics-monitoring/deploy/compose/compose.yaml`
- Create: `stacks/victoriametrics-monitoring/deploy/compose/.env.example`
- Create: `stacks/victoriametrics-monitoring/config/`
- Create: `stacks/victoriametrics-monitoring/hooks/lifecycle.sh`
- Create: `stacks/victoriametrics-monitoring/tests/stack.bats`

**Interfaces:**
- Consumes: Blackbox/VMware Exporter、vmagent、VictoriaMetrics、Grafana、vmalert、Alertmanager 的 Compose 片段。
- Produces: `stack_lifecycle ACTION compose single-node`；数据流为 Exporter → vmagent → VictoriaMetrics，查询为 Grafana → VictoriaMetrics，告警为 vmalert → Alertmanager。

- [ ] **Step 1: 编写 stack 渲染和连接失败测试**

断言依赖顺序、内部 URL、持久卷、非 root/非 privileged 默认值、仅必要端口暴露、VMware Exporter 默认关闭、Alertmanager receiver 安全为空接收器。

- [ ] **Step 2: 运行测试并确认失败**

Run: `.tools/bats/bin/bats stacks/victoriametrics-monitoring/tests/stack.bats`
Expected: FAIL，stack 尚不存在。

- [ ] **Step 3: 实现 stack 元数据、配置和 Compose 覆盖**

`monitorctl` 组合组件 Compose 片段与 stack 覆盖文件；配置 VictoriaMetrics 数据源、vmagent remote write、vmalert datasource/remote write/notifier，以及 Grafana provisioning。`cluster/README.md` 只记录 vminsert/vmselect/vmstorage/vmauth 拓扑，不提供可执行清单。

- [ ] **Step 4: 实现生命周期和轻量健康检查**

健康检查覆盖 VictoriaMetrics、vmagent、vmalert、Alertmanager、Grafana 和已启用 Exporter；备份覆盖 VictoriaMetrics 数据、Grafana 数据和配置快照。

- [ ] **Step 5: 验证并提交**

Run: `monitorctl stack victoriametrics-monitoring validate --mode compose --profile single-node && .tools/bats/bin/bats stacks/victoriametrics-monitoring/tests/stack.bats`
Expected: PASS；Compose `config` 成功。

```bash
git add stacks/victoriametrics-monitoring
git commit -m "feat: add VictoriaMetrics monitoring stack"
```

### Task 9: Nightingale 与 Hybrid 单节点 Compose 架构

**Files:**
- Create: `stacks/nightingale-monitoring/`
- Create: `stacks/hybrid-monitoring/`
- Create: `tests/stacks/nightingale-dataflow.bats`
- Create: `tests/stacks/hybrid-deduplication.bats`

**Interfaces:**
- Consumes: Categraf、Nightingale、VictoriaMetrics、Grafana、Exporter 与 vmagent 组件；MySQL 8 和 Redis 6.2+ 作为 stack 内部支撑服务。
- Produces: 两个 `stack_lifecycle ACTION compose single-node` 实现；Nightingale 使用内部 MySQL/Redis 和 VictoriaMetrics 数据源；hybrid 同时接收 vmagent 与 Categraf 指标但使用独立 job/source 标签和显式采集所有权。

- [ ] **Step 1: 编写 Nightingale 数据流失败测试**

断言 MySQL/Redis 仅在内部网络、密码由生成的 secret 文件提供、Nightingale 等待依赖健康而非仅依赖启动顺序、Categraf 写入 VictoriaMetrics、Grafana 数据源正确。

- [ ] **Step 2: 编写 Hybrid 重复采集失败测试**

同一目标不得同时出现在默认 vmagent scrape 列表与 Categraf input 中；如用户显式开启重叠采集，必须配置不同 `collector` 标签并显示警告。

- [ ] **Step 3: 运行测试并确认失败**

Run: `.tools/bats/bin/bats tests/stacks/nightingale-dataflow.bats tests/stacks/hybrid-deduplication.bats`
Expected: FAIL，两个 stack 尚不存在。

- [ ] **Step 4: 实现两个 stack**

每个 stack 包含 README、`stack.yaml`、single-node profile、cluster 说明、Compose 覆盖、`.env.example`、安全配置、生命周期 hook 和 stack 测试。首次安装生成 MySQL、Nightingale 和 Grafana secret；卸载默认保留数据库与 VictoriaMetrics 数据卷。

- [ ] **Step 5: 渲染与健康验证**

Run: `monitorctl stack nightingale-monitoring validate --mode compose --profile single-node && monitorctl stack hybrid-monitoring validate --mode compose --profile single-node`
Expected: 两个 Compose 项目均成功渲染，不暴露 MySQL/Redis 端口，无默认生产密码。

- [ ] **Step 6: 提交两个 stack**

```bash
git add stacks/nightingale-monitoring stacks/hybrid-monitoring tests/stacks
git commit -m "feat: add Nightingale monitoring stacks"
```

### Task 10: CI、运维文档与最终验收

**Files:**
- Create: `.github/workflows/validate.yml`
- Create: `.github/workflows/compose-smoke.yml`
- Create: `docs/guides/quick-start.md`
- Create: `docs/guides/offline-installation.md`
- Create: `docs/guides/backup-restore.md`
- Create: `docs/guides/upgrade-rollback.md`
- Create: `docs/guides/secrets.md`
- Create: `docs/guides/troubleshooting.md`
- Create: `docs/guides/migration-from-legacy-layout.md`
- Create: `docs/reference/compatibility-matrix.md`
- Create: `docs/reference/adding-a-component.md`
- Create: `docs/reference/adding-a-stack.md`
- Modify: `README.md`
- Create: `CHANGELOG.md`
- Create: `CONTRIBUTING.md`
- Create: `SECURITY.md`
- Create: `tests/acceptance/repository.bats`

**Interfaces:**
- Consumes: 前九个任务提供的命令、Schema、组件和 stacks。
- Produces: `make lint`、`make validate`、`make test`、`make smoke`；中英文入口说明；Ubuntu/Rocky 兼容矩阵；完整操作手册。

- [ ] **Step 1: 编写仓库验收失败测试**

断言 README 不再引用旧仓库名、所有已支持模式有操作文档、所有 stack 标注成熟度、PrometheusAlert 与 `prometheus-vmware` 不存在、secret 扫描覆盖完整工作树。

- [ ] **Step 2: 运行验收测试并确认失败**

Run: `.tools/bats/bin/bats tests/acceptance/repository.bats`
Expected: FAIL，CI 与文档尚未完成。

- [ ] **Step 3: 完成 CI 与文档**

`validate.yml` 执行 Shell/YAML/Schema/Compose/secret 检查；`compose-smoke.yml` 对三条 stack 使用受控版本矩阵执行拉取、启动、健康检查、停止和卷保留检查。兼容矩阵分别列出 Ubuntu 22.04、24.04、Rocky 8、9 的 tested/planned 状态，不把未执行的平台标记为 tested。

- [ ] **Step 4: 执行完整验证**

Run: `make lint && make validate && make test`
Expected: PASS。

Run: `make smoke`
Expected: 三条 Compose single-node stack 的可用服务通过健康检查；因缺少外部 vCenter 凭据而跳过 VMware 集成测试时必须显示明确 SKIP 原因。

- [ ] **Step 5: 做最终安全与范围检查**

Run: `git diff --check && .tools/bats/bin/bats tests/security tests/acceptance`
Expected: PASS；没有 secret、旧目录、`latest` 漂移引用或不受支持模式的成功声明。

- [ ] **Step 6: 提交首个里程碑**

```bash
git add .github docs README.md CHANGELOG.md CONTRIBUTING.md SECURITY.md Makefile tests
git commit -m "docs: complete monitor-hub operator workflow"
```

### Task 11: 里程碑整体审计

**Files:**
- Review: repository-wide diff from `ea2a7b2` through current `HEAD`
- Modify: only files required to fix review findings

**Interfaces:**
- Consumes: Tasks 1–10 的所有交付物。
- Produces: 可进入 Git 历史清理计划的已验证工作树。

- [ ] **Step 1: 审计规范覆盖和提交边界**

逐项将设计规范第 16 节验收标准映射到命令输出或测试；确认每个提交可以独立理解，且无无关改动。

- [ ] **Step 2: 从干净检出执行验证**

Run: `make lint && make validate && make test && make smoke`
Expected: 全部通过或仅出现文档明确允许的外部集成 SKIP。

- [ ] **Step 3: 检查最终状态**

Run: `git status --short && git log --oneline --decorate -12`
Expected: 工作树干净，提交顺序与任务顺序一致。

- [ ] **Step 4: 进入独立历史清理计划**

只有在 vCenter 密码已更换得到明确确认后，才执行 `docs/superpowers/plans/2026-10-21-monitor-hub-credential-history-remediation.md`。
