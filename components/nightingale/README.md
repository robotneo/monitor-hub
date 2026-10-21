# Nightingale

This component expects external MySQL, Redis and VictoriaMetrics services. Their
addresses and credentials are injected at runtime; support services are composed
only by stacks. Set `NIGHTINGALE_IMAGE` to an exact tag or digest.

Use `nightingale_prepare_release_assets VERSION TARGET_DIR` from the lifecycle
hook to prepare the matching upstream database bootstrap SQL and reference
configuration. The resolver checks `MH_NIGHTINGALE_ASSET_SOURCE_DIR` first,
then exact-version files in `packages/`, and only then downloads files from the
matching upstream Git tag. Repository-managed configuration remains the active
configuration; the upstream file is saved as `config.toml.upstream` for review.
