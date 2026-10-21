# Grafana

Grafana is provisioned without committed credentials. Set `GRAFANA_IMAGE` to an
exact tag or digest and inject the admin password using a protected environment
or secret file. `GRAFANA_DATASOURCE_URL` selects the Prometheus-compatible data
source and defaults to the VictoriaMetrics service used by the reference stacks.
