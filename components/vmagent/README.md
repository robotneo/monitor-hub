# vmagent

vmagent reads the Prometheus-compatible scrape file and sends samples to the
explicit VictoriaMetrics `/api/v1/write` endpoint. Set `VMAGENT_IMAGE` to an
exact tag or digest.
