# Cluster topology / 集群拓扑

No executable cluster manifest is shipped yet. Separate vmagent collection from
Categraf host ownership, use vmauth in front of a VictoriaMetrics cluster, and
move MySQL/Redis to managed or independently operated HA services.

当前不提供可执行集群清单。集群化时仍须保持 vmagent 与 Categraf 的采集所有权
分离，并将 MySQL/Redis 迁移到独立高可用服务。
