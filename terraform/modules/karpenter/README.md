# karpenter module

Installs Karpenter with a `gpu-spot` NodePool ready to provision GPU nodes on demand for LLM inference workloads.

## What it creates

- **Karpenter controller IAM role** — via EKS Pod Identity (not IRSA — Pod Identity is Karpenter's new default and doesn't require an OIDC provider trust dance)
- **Node IAM role** — attached to every EC2 instance Karpenter launches (worker, CNI, ECR, SSM policies)
- **SQS queue + EventBridge rules** — spot interruption events flow here so Karpenter can drain nodes gracefully
- **Karpenter Helm chart** — installed in `kube-system` with tolerations for the `CriticalAddonsOnly` taint
- **EC2NodeClass `gpu`** — AL2023 AMI, 100Gi encrypted gp3 root disk
- **NodePool `gpu-spot`** — g5 and g4dn instance families, spot-first with on-demand fallback, `nvidia.com/gpu` taint

## Design decisions

- **Spot-first for GPU workloads** — g5.xlarge spot is ~65% cheaper than on-demand. Inference is more interruption-tolerant than training. The tradeoff is documented in `docs/ADRs/0002-choose-karpenter.md`.
- **`consolidationPolicy: WhenEmpty`, not `WhenUnderutilized`** — for GPU nodes, disrupting a running inference pod is expensive. WhenEmpty is safer at some cost efficiency.
- **`expireAfter: 168h`** — force node rotation every 7 days for security patching. Karpenter drains and replaces automatically.
- **Instance families `[g5, g4dn]`, not just `g5`** — availability of `g5.xlarge` spot varies by AZ. Including `g4dn` gives Karpenter a fallback family with similar cost characteristics.
- **`limits: cpu 100, memory 400Gi`** — a hard cap so runaway workloads can't spin up unlimited GPU nodes and blow the AWS bill. Adjust for your scale.

## Prerequisites

- EKS cluster with Pod Identity Agent addon enabled
- VPC subnets tagged with `karpenter.sh/discovery = <cluster_name>`
- Node security group tagged with `karpenter.sh/discovery = <cluster_name>`

## Usage

```hcl
module "karpenter" {
  source = "../../modules/karpenter"

  cluster_name      = module.eks.cluster_name
  karpenter_version = "1.0.6"

  tags = {
    Project = "paved-road-ai-eks"
  }

  depends_on = [module.eks]
}
```

## How to verify it works

```bash
# Check Karpenter is running
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter

# Check NodePool is ready
kubectl get nodepool gpu-spot

# Deploy a GPU workload and watch Karpenter provision a node
kubectl apply -f examples/gpu-test-pod.yaml
kubectl get nodes -w
```
