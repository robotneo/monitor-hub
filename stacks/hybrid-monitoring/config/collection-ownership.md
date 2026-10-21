# Collection ownership

Default ownership is intentionally disjoint:

- Categraf owns host CPU, memory, disk, process and network inputs.
- vmagent owns Blackbox and optional VMware exporter scraping.

警告 / WARNING: enabling the same Prometheus target in Categraf and vmagent
creates duplicate series and doubles ingestion. If overlap is explicitly needed
for migration testing, preserve `collector="categraf"` in Categraf and
`collector="vmagent"` in vmagent, use a short time window, and alert on duplicate
series before production rollout.
