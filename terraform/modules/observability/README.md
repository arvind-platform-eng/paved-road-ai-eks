# observability module

Installs Prometheus, Grafana, AlertManager, and NVIDIA DCGM exporter.

## What it creates

- **kube-prometheus-stack** — Prometheus, Grafana, AlertManager, node-exporter, kube-state-metrics — one Helm chart
- **DCGM exporter** — DaemonSet on GPU nodes, exposes GPU utilisation, memory, temperature, power draw to Prometheus

## Design decisions

- **kube-prometheus-stack over separate installs** — one operator manages CRDs, ServiceMonitors, PrometheusRules consistently. Separately installing Prometheus/Grafana leads to config drift.
- **DCGM on GPU nodes only** — no point running the exporter on system nodes. NodeSelector `workload-type: gpu` + toleration for `nvidia.com/gpu` taint.
- **`serviceMonitorSelectorNilUsesHelmValues = false`** — this is the flag that trips up most teams. Without it, Prometheus only scrapes ServiceMonitors created by this Helm release. Setting it false makes Prometheus scrape ServiceMonitors from anywhere in the cluster — required for vLLM metrics.

## Dashboards to import

After Grafana is up (`kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80`):

| Dashboard | ID | Purpose |
|-----------|----|---------| 
| NVIDIA DCGM Exporter | 12239 | GPU utilisation, memory, temperature |
| vLLM Metrics | (custom) | Token throughput, request queue depth |
| Karpenter | 20398 | Node provisioning, spot vs on-demand |
| KServe | (custom) | Inference request latency, error rate |

## Usage

```hcl
module "observability" {
  source = "../../modules/observability"

  grafana_admin_password = var.grafana_admin_password

  depends_on = [module.karpenter]
}
```
