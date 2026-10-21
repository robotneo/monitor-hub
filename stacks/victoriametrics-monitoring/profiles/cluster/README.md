# Cluster topology (documentation only)

This profile intentionally has no executable manifest in the first milestone.
A production cluster should separate `vminsert`, `vmselect`, and `vmstorage`,
place `vmauth` in front of the read/write endpoints, and deploy each stateful
role across failure domains. vmagent writes through vmauth to vminsert; Grafana
and vmalert query through vmauth to vmselect.

本目录仅记录后续集群化边界，当前不可直接部署。生产设计应将
`vminsert`、`vmselect`、`vmstorage` 分离，并通过 `vmauth` 提供统一的
读写入口；有状态副本需要跨故障域部署。
