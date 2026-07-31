# Operational runbook

Incident response procedures for the reference architecture. Written for the on-call engineer at 3am.

## GPU node fails to provision

**Symptoms:** InferenceService pod stuck in `Pending`. Karpenter logs show "no matching nodepool" or "insufficient capacity".

**Diagnosis:**

```bash
# Check pod events
kubectl describe pod <pod-name> -n inference

# Check Karpenter logs
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter --tail=100

# Check NodePool status
kubectl get nodepool gpu-spot -o yaml | yq '.status'

# Check whether GPU capacity is available in AZ
aws ec2 describe-spot-instance-requests --region us-east-1 \
  --filters "Name=state,Values=open,active,failed"
```

**Common causes and fixes:**

- **AWS spot capacity exhausted in AZ** — Karpenter falls back to `g4dn` family automatically. If both are exhausted, wait or temporarily allow `on-demand` in the NodePool.
- **NodePool CPU/memory limit hit** — check `limits` in the NodePool spec. Raise if legitimate.
- **Node subnet doesn't have `karpenter.sh/discovery` tag** — Terraform should set this, but verify with `aws ec2 describe-subnets`.
- **Pod tolerations don't match NodePool taints** — pod must tolerate `nvidia.com/gpu` for GPU nodes.

## vLLM pod OOMKilled

**Symptoms:** Pod restarts continuously with `OOMKilled` exit reason.

**Diagnosis:**

```bash
kubectl describe pod <pod-name> -n inference | grep -i oom
kubectl top pod <pod-name> -n inference --containers
```

**Common causes and fixes:**

- **`gpu-memory-utilization` too high** — vLLM tries to grab 90% by default. Lower to 0.85 if you need memory headroom for other processes.
- **`max-model-len` too high** — KV cache scales with context length. 8192 works for 7B models on 24GB VRAM; 16384 may not.
- **Wrong dtype** — bfloat16 halves memory vs float32. Verify the args pass `--dtype bfloat16`.

## Spot interruption during peak traffic

**Symptoms:** Requests fail with 503 during a 2-minute window. AlertManager fires `HighErrorRate`.

**Response:**

1. Check whether Karpenter received the interruption notice:
   ```bash
   kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter | grep interruption
   ```

2. Verify PodDisruptionBudget prevented total outage:
   ```bash
   kubectl get pdb -n inference
   ```

3. If the workload lacks a PDB, add one immediately:
   ```yaml
   apiVersion: policy/v1
   kind: PodDisruptionBudget
   metadata:
     name: mistral-7b
     namespace: inference
   spec:
     minAvailable: 1
     selector:
       matchLabels:
         app: mistral-7b
   ```

**Post-incident:** if spot interruptions are frequent (>5/day), consider raising the on-demand base capacity in the NodePool.

## Prometheus running out of disk

**Symptoms:** Grafana dashboards show gaps. Prometheus logs show `disk full` or `WAL full`.

**Fix:**

```bash
# Immediate: reduce retention
kubectl edit prometheus -n monitoring kube-prometheus-stack-prometheus
# Change spec.retention from 15d to 7d

# Long-term: expand the PVC
kubectl edit pvc -n monitoring prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0
# Increase spec.resources.requests.storage
```

## ArgoCD out of sync

**Symptoms:** ApplicationSet shows `OutOfSync` state. Manual `kubectl` changes aren't being reverted (or are being reverted when they shouldn't).

**Diagnosis:**

```bash
argocd app get platform --show-params
argocd app diff platform
```

**Common causes and fixes:**

- **Manual `kubectl apply` on a managed resource** — ArgoCD will revert it on next sync. If the manual change was correct, commit it to git.
- **Sync policy set to `manual`** — check `syncPolicy.automated` is present in the ApplicationSet spec.
- **RBAC drift** — some resources ArgoCD lacks permission to manage. Check ArgoCD's ClusterRole.

## Escalation

| Severity | Who to page |
|----------|-------------|
| Total inference outage | Platform lead (Arvind) + product on-call |
| Partial degradation | Platform on-call |
| Non-urgent | Slack #platform-eng, address next business day |

## Post-incident review template

Every incident with >5 min of user impact gets a post-incident review. See `docs/templates/postmortem.md` (todo).
