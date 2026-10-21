# VMware Exporter

The committed file is a template only. Provide `VMWARE_VSPHERE_HOST`,
`VMWARE_VSPHERE_USER` and `VMWARE_VSPHERE_PASSWORD` from a protected runtime
environment or render the file from a secret manager. Never commit the rendered
file. Set `VMWARE_EXPORTER_IMAGE` to an exact tag or digest.
