# Observability module — a walkthrough

*File: `terraform/modules/observability/main.tf`*

This is my working explanation of the observability module. Written in the order I'd say it in an interview or code review — outside layers first, details only on request.

---

## Layer 1 — Purpose

This module installs a full observability stack on the EKS cluster — Prometheus for metrics collection, Grafana for visualisation, AlertManager for alerting, and NVIDIA DCGM exporter for GPU-specific telemetry.

---

## Layer 2 — Inputs and outputs

The module takes three inputs — the Helm chart version for kube-prometheus-stack, the version for DCGM exporter, and a sensitive Grafana admin password variable that is never logged. It produces no Terraform outputs, because everything it creates is Kubernetes-native and discoverable via `kubectl` rather than by downstream Terraform modules.

---

## Layer 3 — The story in two chunks

The file has two logical sections.

First, it installs `kube-prometheus-stack` via Helm into a dedicated `monitoring` namespace. This one Helm chart bundles Prometheus, Grafana, AlertManager, node-exporter, and kube-state-metrics — five separate observability components that share configuration through a single operator. Grafana gets a persistent volume for dashboards, Prometheus retains 15 days of metrics on a 50 GiB PVC, and AlertManager has its own 5 GiB volume for alert state. Second, it installs the NVIDIA DCGM exporter as a DaemonSet, but only on GPU nodes — using a nodeSelector for `workload-type: gpu` and a toleration for the `nvidia.com/gpu` taint. DCGM registers itself with Prometheus via a ServiceMonitor CRD so GPU utilisation, memory, temperature, and power draw all flow into the same metrics store as everything else.

---

## Layer 4 — Design decisions worth calling out

Four choices are worth mentioning in a design conversation.

**kube-prometheus-stack over installing Prometheus and Grafana separately.** Both approaches work, but the stack chart ships an opinionated bundle with a single operator managing CRDs, ServiceMonitors, and PrometheusRules consistently. Installing Prometheus, Grafana, node-exporter, and kube-state-metrics as four separate Helm releases means four sets of upgrade paths and four opportunities for configuration drift. The stack chart is the community-standard choice — nobody assembles it manually anymore.

**`serviceMonitorSelectorNilUsesHelmValues = false`.** This is the single flag that trips up most teams the first time they install kube-prometheus-stack. By default, Prometheus only scrapes ServiceMonitors created by the same Helm release, so any ServiceMonitor deployed elsewhere in the cluster — including the one DCGM creates, and the one vLLM will create later — is silently ignored. Setting this flag to `false` makes Prometheus scrape ServiceMonitors from any namespace. Without it, the observability stack is technically running but not observing anything else.

**DCGM as a DaemonSet with nodeSelector, not on every node.** DCGM has no reason to run on the system t3.medium nodes — they don't have GPUs to measure. Constraining it to `workload-type: gpu` nodes saves resources and avoids spurious "no GPU found" errors in the DCGM logs. The toleration for `nvidia.com/gpu:NoSchedule` is required because Karpenter's GPU nodes carry that taint to keep non-GPU workloads off.

**Persistent volumes sized for a reference architecture, not production.** Prometheus at 50 GiB with 15-day retention is generous for a dev environment and undersized for a real production cluster. The trade-off is deliberate: the numbers are conservative enough to fit a low-cost setup while high enough that a curious engineer can browse a few days of metrics before the volume fills. Production would use Thanos or Grafana Mimir for long-term retention, both of which use object storage instead of PVCs.

---

## Layer 5 — Zoom-ins (only when asked)

### If asked: "Walk me through how vLLM metrics get into Grafana"

There's a four-step chain. First, vLLM's OpenAI server exposes a Prometheus-compatible `/metrics` endpoint on port 8080 — this is built into the vLLM image, no extra sidecar needed. Second, the InferenceService spec includes a ServiceMonitor resource that tells Prometheus which pods to scrape and on which port. Third, because we set `serviceMonitorSelectorNilUsesHelmValues = false`, Prometheus picks up this ServiceMonitor even though it lives in the `inference` namespace and Prometheus lives in `monitoring`. Fourth, once Prometheus is scraping, a Grafana dashboard queries Prometheus using PromQL expressions like `rate(vllm_request_success_total[5m])` to render token throughput or request latency. If any link in this chain breaks — missing `/metrics` endpoint, missing ServiceMonitor, wrong Helm flag, wrong PromQL — the dashboards silently show empty panels rather than errors, which is the most common observability failure mode.

### If asked: "Why 15-day retention?"

Two reasons. First, it's the point at which the storage cost curve starts to bite for a small setup — beyond 15 days, the 50 GiB PVC would need to grow to hundreds of GiB and the read performance of local EBS starts to degrade Prometheus queries. Second, 15 days is long enough to observe weekly patterns (weekday vs weekend traffic, Monday morning spikes) but short enough that a curious engineer isn't waiting minutes for range queries to complete. For real production observability, the pattern is short retention in local Prometheus and long retention in an object-store-backed system like Thanos, which is a different architecture altogether — planned for the roadmap but not implemented in v1.

### If asked: "Why is the Grafana admin password a sensitive variable rather than a random_password resource?"

Two considerations. First, keeping it as a variable means the password is set once and remains stable across `terraform apply` runs, so the operator can log into Grafana with the same credentials after every deploy. If it were a `random_password` resource, it would rotate on every apply unless we added a keeper block, and would need to be surfaced through an output — which then appears in the state file anyway. Second, marking the variable `sensitive = true` in Terraform ensures it's masked in plan and apply output, and in Jenkins it comes from the `grafana-admin-password` secret via `withCredentials`, so it never appears in logs. The trade-off we accepted: the operator must remember or securely store the password themselves. In a real production setup this would go through External Secrets Operator with the actual password in AWS Secrets Manager, but that adds complexity we don't need for a reference architecture.