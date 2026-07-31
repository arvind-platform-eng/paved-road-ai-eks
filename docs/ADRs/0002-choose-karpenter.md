# ADR 0002: Choose Karpenter for GPU node autoscaling

**Status:** Accepted
**Date:** 2026-01-15
**Author:** Arvind Kumar

## Context

GPU inference workloads have three properties that make node autoscaling non-trivial:

1. **GPU nodes are expensive** — g5.xlarge on-demand is ~$1.00/hour. Idle nodes burn cash.
2. **Cold-start is slow** — node provisioning + image pull + model load = 3–5 minutes.
3. **Spot pricing is volatile** — g5 spot availability varies by AZ and time of day.

The autoscaler must handle spot interruption gracefully, provision the right instance type quickly, and consolidate nodes when workloads shrink.

## Decision

Use Karpenter v1.x for all workload node provisioning. Retain a small EKS-managed system node group only for cluster-critical components (CoreDNS, Karpenter itself).

## Consequences

### Positive

- **Provisioning is ~40 seconds** vs. Cluster Autoscaler's ~2 minutes. For GPU workloads where cold starts already cost ~5 minutes, this matters.
- **Spot + on-demand mixing is native** — one NodePool declares both, Karpenter picks based on price and availability.
- **Instance-family flexibility** — declaring `["g5", "g4dn"]` lets Karpenter fall back when g5.xlarge spot capacity is unavailable in the primary AZ.
- **SQS-based interruption handling** — 2-minute spot warning triggers automatic pod drain via EventBridge → SQS → Karpenter.
- **Consolidation reduces cost** — Karpenter continuously evaluates whether workloads could fit on cheaper instance mixes and rebalances.
- **No cluster autoscaler complexity** — one component handles both scale-up and scale-down.

### Negative

- **IAM setup is more involved** than Cluster Autoscaler. Karpenter needs broad EC2 permissions (RunInstances, TerminateInstances, CreateFleet) plus SSM read for AMI discovery.
- **Debugging spot interruptions requires SQS insight** — new team members need training on the interruption flow.
- **NodePool limits are a hard cap, not soft** — hitting the CPU/memory limit blocks all new workloads. Must monitor and alert on utilisation.
- **`consolidationPolicy: WhenUnderutilized` is dangerous for GPU workloads** — it can disrupt running inference. We use `WhenEmpty` instead, at a small cost efficiency loss.

### Rejected alternatives

- **Cluster Autoscaler** — slower provisioning, no native spot/on-demand mixing, requires per-instance-type node groups. Would need 4–6 separate node groups to match Karpenter's flexibility.
- **Bare EC2 Auto Scaling Groups** — no Kubernetes awareness. Rejected immediately.
- **AWS Fargate for GPU** — Fargate does not support GPU workloads as of 2026.

## Operational notes

- Monitor `karpenter_nodes_created_total` and `karpenter_nodes_terminated_total` metrics — sudden spikes indicate churn.
- Alert on `karpenter_disruption_evictions_total` when it exceeds a baseline — usually means aggressive spot reclaim.
- Review NodePool limits quarterly. Traffic grows.

## References

- [Karpenter documentation](https://karpenter.sh/docs/)
- [Karpenter v1 upgrade guide](https://karpenter.sh/docs/upgrading/upgrade-guide/)
