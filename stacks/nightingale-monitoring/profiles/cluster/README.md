# Cluster topology / 集群拓扑

This milestone does not ship an executable cluster manifest. Production should
use external high-availability MySQL and Redis, a VictoriaMetrics cluster behind
vmauth, and multiple Nightingale instances sharing metadata services.

当前只提供边界说明：生产环境应使用外部高可用 MySQL/Redis、由 vmauth 统一
入口的 VictoriaMetrics 集群，以及共享元数据服务的多 Nightingale 实例。
