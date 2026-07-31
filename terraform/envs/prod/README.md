# prod environment

Will mirror `dev/` with production-hardened settings:

- Multi-AZ NAT gateways
- Larger system node group (3 nodes, m5.large)
- Longer Prometheus retention (90 days)
- Grafana behind SSO
- Backup + DR runbook
- Separate AWS account with cross-account state locking

Not implemented in v1. Priority is getting `dev/` working end-to-end first.

See ROADMAP in the root README.
