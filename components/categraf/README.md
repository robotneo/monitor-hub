# Categraf

The default Compose fragment performs container-level collection only. Host
filesystem mounts are isolated in `host-collection.compose.yaml` and require the
explicit `host-collection` Compose profile. Set `CATEGRAF_IMAGE` to an exact tag
or digest.
