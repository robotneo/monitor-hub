# Adding a component / 新增组件

1. 建立 `components/<name>/component.yaml` 和 `versions.yaml`。
2. 只声明真正实现的模式，并设置支持级别。
3. 添加默认无凭据配置、部署文件、README 与 `hooks/lifecycle.sh`。
4. hook 必须实现统一动作签名，并对不支持模式返回错误。
5. 版本解析优先离线包/本地镜像；在线只解析稳定版并记录版本与 digest。
6. 为元数据、配置连接、离线行为和卸载数据保留编写 Bats 测试。
7. 执行 `make lint validate test` 与工作树 secret 扫描。

Schema details are in `component-contract.md`. Do not publish host ports unless
the standalone component contract requires them; stacks should minimize exposure.
