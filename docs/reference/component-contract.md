# Component contract

An implemented component lives at `components/<name>/` and owns its reusable
configuration, deployment adapters, lifecycle hook, tests and operator guide.

`component.yaml` is validated by `schemas/component.schema.json`. It records:

- stable identity (`name`, `kind`) and upstream repository;
- repository `support` level;
- service ports and host paths;
- validated operating systems and CPU architectures;
- implemented deployment `modes`;
- one non-secret health-check target.

`versions.yaml` is validated separately. It describes release discovery, local
artifact filename templates, image repositories and tested compatibility. Actual
resolved versions and image digests belong to runtime state, not this metadata.

Do not list a platform or mode before its tests and operator documentation exist.
Configuration examples must contain placeholders only; secrets are injected at
runtime from protected external files or the target platform's secret mechanism.
