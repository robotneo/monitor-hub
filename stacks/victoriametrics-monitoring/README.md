# VictoriaMetrics monitoring stack

Data flow: exporters → vmagent → VictoriaMetrics; Grafana queries
VictoriaMetrics; vmalert evaluates rules and sends notifications to
Alertmanager. Only Grafana is published to the host by default.

## Quick start / 快速开始

```bash
bin/monitorctl stack victoriametrics-monitoring validate --mode compose --profile single-node
bin/monitorctl stack victoriametrics-monitoring install --mode compose --profile single-node
```

`monitorctl` resolves current stable image versions and deploys immutable image
digests. Existing compatible local images are used before pulling. If the
network or GitHub is slow, the command reports the failed image or URL so the
image can be loaded locally and retried.

`monitorctl` 会把当前稳定版本解析为不可变镜像 digest；如果本机已有兼容
镜像则优先使用。网络不可用或 GitHub 较慢时会明确提示失败目标，镜像手工
导入后可直接重试。

VMware collection is disabled by default. To enable it, create the protected
runtime file shown by `config/vmware-exporter/config.yml.example`, set
`COMPOSE_PROFILES=vmware`, and select the VMware vmagent configuration:

```bash
export COMPOSE_PROFILES=vmware
export VMAGENT_CONFIG_FILE=prometheus-with-vmware.yml
```

Do not commit the rendered VMware configuration. `uninstall` preserves data;
add `--purge-data --yes` only when permanent deletion is intended.
