# prometheus-everything
关于Prometheus全套监控体系的docker compose运行启动，目前该存储库包含使用 Prometheus 、Grafana、Alertmanager、和 PrometheusAlert 为 Vmware ESXi 集群部署基本监控环境的文件，后续将新增node_exporter、snmp_exporter、blackbox_exporter等相关组件通过docker compose运行启动的配置文件。

### 更新

- Prometheus、Grafana、Alertmanager、PrometheusAlert、vmware_exporter适配
- 后续

### 先决条件

- 安装好docker engine

### 目录说明

- alert目录是关于PrometheusAlert的配置文件。
- alertmanager目录是关于alertmanager的配置文件。
- compose目录是通过docker compose启动全套Prometheus+Alertmanager+Grafana+PrometheusAlert等配置文件。
- prometheus目录是通过prometheus的配置文件。
- vmware目录是运行vmware_exporter的配置文件目录。

### 功能和配置

#### Prometheus

- Prometheus 服务作为从 quay.io（红帽提供）拉取的容器运行。
- 该服务将侦听端口 9090。
- Prometheus 服务的配置位于该 prometheus 目录中，确保在运行之前将其复制到服务器上的 /opt/prometheus/conf

```bash
wget https://raw.githubusercontent.com/robotneo/prometheus-everything/main/prometheus/prometheus.yml -O /opt/prometheus/conf/prometheus.yml
```

- 在配置文件/opt/prometheus/conf/prometheus.yml中更改与ESXi集群相关的环境变量。
- Prometheus 会将指标保存 30 天。
- docker compose创建一个用于持久保存指标的卷。
- Prometheus默认使用了本地存储，如果需要解决单节点限制，可以对接远程存储接口，如：InfluxDB数据库作为Prometheus的存储等。

#### Grafana

- Grafana 服务作为从 docker.io 拉取的容器运行
- 该服务将侦听端口 3000。
- docker compose创建一个用于持久保存数据的卷
- 默认用户名和密码为admin
- 登陆后，可配置数据源和VMWare的模版，推荐 Grafana ID：11243

#### Alertmanager

- Alertmanager 服务作为从 quay.io（红帽提供）拉取的容器运行。
- 该服务将侦听端口 9093。
- Alertmanager 服务器的配置位于该 alertmanager 目录中，确保在运行之前将其复制到服务器上的 /opt/alertmanager/conf

```bash
wget https://raw.githubusercontent.com/robotneo/prometheus-everything/main/alertmanager/alertmanager.yml -O /opt/alertmanager/conf/alertmanager.yml
```

- 告警规则配置文件在：/opt/prometheus/rules 中，列出常见的服务告警规则。

```bash
wget https://raw.githubusercontent.com/robotneo/prometheus-everything/main/prometheus/esxi_rule.yml -O /opt/prometheus/rules/esxi_rule.yml
```

- 告警规则和告警路由如果需要得到告警信息，需要自行添加相关webhook，邮件配置，短信配置等，因结合PrometheusAlert，相关配置请参考：https://github.com/feiyu563/PrometheusAlert

#### PrometheusAlert

- PrometheusAlert 服务作为从 docker.io 拉取的容器运行。
- 该服务将侦听端口 8080。
- PrometheusAlert 服务的配置位于该 alert 目录中，确保在运行之前将其复制到服务器上的 /opt/prometheusalert-center/conf
  
```bash
wget https://raw.githubusercontent.com/robotneo/prometheus-everything/main/alert/app.conf -O /opt/prometheusalert-center/conf/app.conf
```

#### vmware_exporter

- vmware_exporter 服务作为从 docker.io 拉取的容器运行。
- 该服务将侦听端口 9272。
- vmware_exporter 服务的配置位于该 vmware 目录中，确保在运行之前将其复制到服务器上的 /opt/vmware
  
```bash
wget https://raw.githubusercontent.com/robotneo/prometheus-everything/main/vmware/config.yml -O /opt/vmware/config.yml
```

#### blackbox_exporter

- blackbox_exporter 服务作为从 quay.io（红帽提供） 拉取的容器运行。
- 该服务将侦听端口 9115。
- blackbox_exporter 服务的配置位于该 blackbox 目录中，确保在运行之前将其复制到服务器上的 /opt/blackbox

 > 查看配置文件说明请查看：https://github.com/prometheus/blackbox_exporter



### 运行启动

- 前提：安装docker

```bash
# 启动 -p 代表项目名称为prom
wget https://raw.githubusercontent.com/robotneo/prometheus-everything/main/compose/compose.yml -O ~/compose.yml
sudo docker compose -f compose.yml -p prom up -d
# 停止
sudo docker compose -p prom down -v
# 查看
sudo docker compose -p prom ps -a
```
