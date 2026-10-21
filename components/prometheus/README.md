# Prometheus

This component preserves the existing Prometheus rules while replacing host IPs
and `/opt` paths with service discovery and the monitor-hub path contract.

Set `PROMETHEUS_IMAGE` to an exact tag or digest, then run:

```bash
bin/monitorctl component prometheus install --mode compose
```

Copy `config/targets/vmware.yml.example` outside Git, replace the placeholder,
and mount the rendered configuration below `${MH_CONFIG_DIR}/prometheus`.
