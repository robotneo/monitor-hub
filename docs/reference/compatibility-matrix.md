# Compatibility matrix / 兼容矩阵

“Contract-covered” means platform detection and path behavior are automated-test
covered. It does not claim a real host deployment has run.

| Platform | Contract tests | Real host install | Status |
|---|---:|---:|---|
| Ubuntu 22.04 amd64/arm64 | Yes | Not yet recorded | Planned |
| Ubuntu 24.04 amd64/arm64 | Yes | Not yet recorded | Planned |
| Rocky Linux 8 amd64/arm64 | Yes | Not yet recorded | Planned |
| Rocky Linux 9 amd64/arm64 | Yes | Not yet recorded | Planned |

| Deployment mode | Current status |
|---|---|
| Docker Compose single-node | Preview, executable |
| Native | Contract boundary only; no success claim |
| Standalone Docker | Contract boundary only; no success claim |
| Kubernetes | Planned; no executable manifests in this milestone |

真实主机测试完成后必须记录日期、架构、Docker/Compose 版本和测试 commit，才能将
状态改为 Tested。
