# Monitor Hub Repository Design

[English](2026-10-21-monitor-hub-repository-design.md) | [中文](2026-10-21-monitor-hub-repository-design.zh-CN.md)

**Status:** Approved conversational design; awaiting written-spec review  
**Date:** 2026-10-21  
**Repository:** `robotneo/monitor-hub`

## 1. Purpose

`monitor-hub` is a maintainable deployment repository for monitoring and alerting components. It must support both independent component deployment and complete reference architectures without duplicating shared configuration.

The repository is intended for operators deploying on Ubuntu 22.04/24.04 LTS and Rocky Linux 8/9. It will ultimately cover native Shell/systemd, Docker, Docker Compose, and Kubernetes workflows. The first implementation milestone makes three Docker Compose single-node architectures usable while establishing, but not claiming production readiness for, the other deployment modes.

## 2. Goals

- Keep the existing repository name `monitor-hub`.
- Give every component a consistent, independently usable directory and lifecycle contract.
- Provide complete reference stacks that compose components rather than copy them.
- Cover installation, configuration, start, stop, restart, status, upgrade, backup, restore, validation, diagnosis, and uninstall.
- Prefer compatible local packages and cached images; otherwise resolve and download the latest stable upstream release.
- Record the exact resolved binary version and container digest after installation.
- Support safe offline installation and actionable diagnostics when networks are unavailable or slow.
- Keep secrets out of Git and detect accidental credential commits automatically.
- Validate configuration and deployment artifacts in CI.
- Make future components and stacks predictable to add and review.

## 3. Non-goals for the First Milestone

- Production-ready native deployments for every component.
- Production-ready single-container Docker deployments for every component.
- Production-ready Kubernetes deployments.
- A working VictoriaMetrics cluster topology.
- Zabbix deployment content.
- Additional empty component directories that do not yet contain an implementation.

Kubernetes conventions are defined now, using Helm first and Kustomize for environment overlays. Cluster topology and non-Compose deployment modes remain documented extension points until separately implemented and tested.

## 4. Current Repository Findings

The current repository is a small Prometheus-oriented Docker Compose deployment containing Prometheus, Grafana, Alertmanager, PrometheusAlert, Blackbox Exporter, and VMware Exporter configuration.

The migration must correct these issues:

- README references the obsolete name `prometheus-everything`.
- Components and composition are mixed in a monolithic Compose file.
- Images use mutable `latest` tags without recording the deployed digest.
- Host IPs and `/opt` paths are hard-coded.
- Containers generally run as root and privileged without demonstrated need.
- There is no consistent lifecycle, state, backup, rollback, validation, or compatibility contract.
- A plaintext vCenter administrator credential exists in public Git history.
- PrometheusAlert is no longer wanted.

## 5. Repository Structure

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

### 5.1 Boundaries

- `components/` owns independently deployable components.
- `stacks/` owns composition, dependency ordering, cross-component wiring, and stack-specific overrides.
- A stack references component-owned configuration and does not keep copied component defaults.
- `bin/monitorctl` is the operator-facing entry point.
- `lib/` contains reusable lifecycle behavior and platform adapters.
- `tools/` and `Makefile` are maintainer-facing.
- `packages/` is a local artifact drop location. Package binaries are ignored by Git; only documentation and explicitly approved checksum manifests are committed.

## 6. Component Contract

Each implemented component follows this layout:

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

`component.yaml` declares the component type, upstream project, dependencies, ports, data paths, health checks, supported operating systems, CPU architectures, and deployment modes. A deployment mode must not be marked supported until its validation and smoke checks pass.

`versions.yaml` describes known compatible versions and artifact locations. It does not force all new installations to use a repository-pinned version; version resolution follows the policy in section 10.

## 7. Stack Contract

Each stack follows this layout:

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

`stack.yaml` is the source of truth for component membership, dependency order, supported profiles, supported deployment modes, required ports, storage, and health checks.

The first milestone makes only `single-node` plus Docker Compose usable. `cluster/README.md` defines future topology and prerequisites without providing unverified manifests.

## 8. Reference Architectures

### 8.1 `victoriametrics-monitoring`

- Exporters
- vmagent
- VictoriaMetrics single-node
- Grafana
- vmalert
- Alertmanager

Exporters feed vmagent, vmagent writes to VictoriaMetrics, Grafana queries VictoriaMetrics, and vmalert evaluates rules against VictoriaMetrics and sends notifications to Alertmanager.

### 8.2 `nightingale-monitoring`

- Categraf
- Nightingale
- VictoriaMetrics single-node
- Grafana

Categraf collects metrics, VictoriaMetrics stores them, Nightingale provides monitoring and alerting workflows, and Grafana provides visualization.

### 8.3 `hybrid-monitoring`

- Exporters
- vmagent
- Categraf
- Nightingale
- VictoriaMetrics single-node
- Grafana

This route supports environments where Prometheus-compatible exporters and Categraf coexist. Collection paths must use explicit labels and job naming so duplicate series can be identified and avoided.

## 9. Operator Interface and Lifecycle

Examples:

```bash
monitorctl component prometheus install --mode native
monitorctl component vmware-exporter status --mode docker
monitorctl stack victoriametrics-monitoring install --mode compose --profile single-node
```

Supported lifecycle actions:

```text
install configure start stop restart status
upgrade backup restore uninstall validate doctor
```

Common options include `--version`, `--dry-run`, `--yes`, and `--purge-data`. Destructive data deletion requires `--purge-data`; `--yes` only suppresses interaction and does not imply data deletion.

Each modifying operation follows this transaction:

1. Detect the operating system, version, package manager, init system, and CPU architecture.
2. Validate privileges, ports, storage, dependencies, and network prerequisites.
3. Resolve compatible artifacts.
4. Verify checksums and container metadata when available.
5. Back up the existing deployment when the action can replace data or configuration.
6. Render configuration into a staging directory.
7. Run syntax and semantic validation.
8. Apply the change.
9. Run health checks.
10. Persist the exact installed version, container digest, configuration fingerprint, and action result.

If validation fails, nothing is applied. If application or health checks fail, the command preserves diagnostic logs and rolls back when the previous state is known and rollback is safe. Otherwise it stops with explicit recovery instructions.

## 10. Artifact and Version Policy

Artifact selection order is:

1. An explicitly requested compatible version or local artifact.
2. A compatible artifact already present in `packages/` or the runtime cache.
3. The latest stable upstream release resolved online, excluding prerelease versions such as alpha, beta, and release candidate builds.

For an online installation, `monitorctl` resolves the current stable release to an exact version before downloading. Container images are recorded by immutable digest after pull. The deployment state therefore remains reproducible even though the initial selection policy is “latest stable.”

When a download fails or is slow, the command reports:

- the attempted source and failure reason;
- the required filename, exact version, OS, and architecture;
- the expected local destination;
- the expected checksum when known;
- supported proxy, GitHub mirror, and container registry mirror configuration;
- the exact retry command.

Untrusted mirrors are never selected automatically.

## 11. Host Filesystem Contract

```text
/etc/monitor-hub/          Rendered configuration and non-secret settings
/var/lib/monitor-hub/      Deployment state and component data references
/var/cache/monitor-hub/    Downloaded artifacts and cached metadata
/var/log/monitor-hub/      Command and component deployment logs
/var/backups/monitor-hub/  Timestamped backups and restore metadata
```

Secret files must have restrictive permissions and remain outside Git. File ownership and service users are component-specific; root and privileged containers are not used unless a documented capability requires them.

## 12. Security and Secret Handling

- Real secrets are never stored in committed configuration or examples.
- `.env.example` and example YAML files contain placeholders only.
- Secrets enter through protected environment files, mounted secret files, Docker secrets where applicable, or Kubernetes Secrets/external secret providers in future Kubernetes work.
- Logs redact values from known secret fields.
- CI scans new commits for likely credentials.
- VMware configuration becomes a sanitized template; the exposed credential is never copied into the new structure.
- The operator must rotate the exposed vCenter credential before repository history is rewritten.

### 12.1 History Remediation

History remediation is a separately gated destructive step even though it is part of the approved project scope:

1. Confirm the exposed vCenter credential has been rotated.
2. Create and verify a recoverable mirror backup and record all remote refs.
3. Rewrite every affected ref to remove the secret-bearing file contents.
4. Verify the removed value and secret patterns are absent from rewritten history.
5. Force-push rewritten branches and tags using explicit ref targets.
6. Document that existing clones must be discarded or carefully rebased onto the rewritten history.

No history rewrite or force-push occurs before the rotation confirmation and a final pre-push review.

## 13. Migration Mapping

- Existing Prometheus configuration moves to `components/prometheus/` and becomes parameterized.
- Existing Alertmanager configuration moves to `components/alertmanager/`; PrometheusAlert routing is removed and replaced with safe examples.
- Existing Grafana Compose content becomes a component definition without bundled credentials.
- Existing Blackbox Exporter configuration moves to `components/blackbox-exporter/`.
- Existing VMware Exporter configuration moves to `components/vmware-exporter/` as a sanitized template.
- Existing monolithic Compose files are replaced by component definitions and the three approved stacks.
- `alert/` and all PrometheusAlert configuration are removed.
- No `prometheus-vmware` stack is created or retained.
- Old hard-coded host addresses and paths become documented variables with safe defaults where possible.

## 14. Validation and CI

The validation suite includes:

- Shell syntax checking, formatting, and static analysis.
- YAML validation and schema validation for `component.yaml` and `stack.yaml`.
- Docker Compose rendering and dependency checks.
- Prometheus and Alertmanager configuration validation where their official tools support it.
- Secret scanning.
- Unit tests for lifecycle dispatch, platform detection, version selection, dry-run behavior, and destructive-operation guards.
- Lightweight Compose smoke tests for the three single-node stacks.
- Compatibility checks for Ubuntu 22.04/24.04 and Rocky Linux 8/9 using disposable test environments where feasible.
- Helm template, Kustomize build, and Kubernetes schema rendering checks for framework examples, without claiming production support.

The maintainer entry points are:

```bash
make lint
make validate
make test
make smoke
```

## 15. Documentation

The repository documents:

- Quick start for each usable stack.
- Component-level deployment and lifecycle actions.
- Compatibility and support matrix.
- Offline installation and mirror configuration.
- Backup and restore procedures.
- Upgrade and rollback procedures.
- Secret management.
- Adding a component.
- Adding a stack.
- Troubleshooting and diagnostic collection.
- Migration from the old repository layout.

Every component and stack README states its support maturity per deployment mode: planned, experimental, tested, or production-ready.

## 16. Acceptance Criteria for the First Milestone

- The repository retains the name `monitor-hub`.
- PrometheusAlert and the proposed `prometheus-vmware` stack are absent.
- Existing retained components are migrated into the component contract and contain no committed real credentials.
- The three approved stacks have usable, validated Docker Compose single-node profiles.
- Cluster profiles contain documentation only and cannot be invoked as supported deployments.
- `monitorctl` implements the full lifecycle interface with safety guards; unsupported actions fail clearly rather than pretending success.
- Local compatible artifacts take precedence over downloads.
- Online installation resolves the latest stable release to a recorded exact version and digest.
- Network failures provide actionable offline instructions.
- Ubuntu 22.04/24.04 and Rocky Linux 8/9 are represented in compatibility validation.
- CI validates Shell, YAML, Compose, configuration, secrets, and lifecycle behavior.
- The credential-history rewrite remains blocked until credential rotation and final destructive-action review are confirmed.

## 17. Implementation Decomposition

The implementation plan should be split into independently reviewable workstreams:

1. Security remediation in the working tree and repository safeguards.
2. Metadata schemas, common directory skeleton, and documentation conventions.
3. `monitorctl`, common lifecycle libraries, platform adapters, state, artifact resolution, and safety guards.
4. Migration of existing retained components.
5. New VictoriaMetrics, vmagent, vmalert, Nightingale, and Categraf component definitions.
6. The three Docker Compose single-node stacks.
7. Validation, smoke tests, CI, and operator documentation.
8. Separately gated Git history rewrite after credential rotation.

Each workstream must produce a testable commit and must not claim support for an unverified deployment mode.
