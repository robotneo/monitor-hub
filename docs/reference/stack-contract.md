# Stack contract

A stack lives at `stacks/<name>/` and composes reusable components. It owns only
dependency order, cross-component wiring, profile-specific overlays and operator
documentation. It must not copy component defaults.

`stack.yaml` is validated by `schemas/stack.schema.json`. It declares:

- component references and their enabled profiles;
- internal `supporting_services` such as MySQL or Redis;
- deterministic `dependency_order`;
- named profiles and their purpose;
- implemented deployment modes and repository support level.

Every profile referenced by a component must exist in the same file. The first
milestone supports only the `single-node` Compose profile. Cluster directories
may document future topology but must not contain unvalidated deployment claims.
