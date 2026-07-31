# eks-cluster module

Provisions an EKS cluster with:

- VPC with public + private subnets across 2 AZs
- Single NAT gateway in non-prod (cost saving), one per AZ in prod
- EKS control plane with public + private API endpoints
- Small managed node group for cluster-critical workloads (CoreDNS, Karpenter)
- Pod Identity + IRSA enabled — Karpenter uses Pod Identity, workloads can choose
- Discovery tags applied for Karpenter (`karpenter.sh/discovery`)

## Design decisions

- **Single NAT gateway in dev** — saves ~$32/month per extra NAT. Trade-off: no NAT HA in dev. Acceptable for a reference architecture.
- **System nodes tainted `CriticalAddonsOnly`** — prevents random workloads from landing here. Only tolerating pods (CoreDNS, Karpenter) run on system nodes.
- **No cluster autoscaler** — Karpenter replaces it entirely for workload nodes.

## Usage

```hcl
module "eks" {
  source = "../../modules/eks-cluster"

  cluster_name       = "paved-road-ai-dev"
  environment        = "dev"
  kubernetes_version = "1.30"
  availability_zones = ["us-east-1a", "us-east-1b"]

  tags = {
    Project = "paved-road-ai-eks"
    Owner   = "arvind"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `cluster_name` | Name of the EKS cluster | `string` | – | ✓ |
| `environment` | Environment name (dev, staging, prod) | `string` | – | ✓ |
| `availability_zones` | AZ list | `list(string)` | – | ✓ |
| `kubernetes_version` | Kubernetes version | `string` | `"1.30"` | – |
| `vpc_cidr` | VPC CIDR block | `string` | `"10.0.0.0/16"` | – |

## Outputs

| Name | Description |
|------|-------------|
| `cluster_name` | EKS cluster name |
| `cluster_endpoint` | API server endpoint |
| `oidc_provider_arn` | For IRSA setup on downstream modules |
| `private_subnet_ids` | Used by Karpenter for node placement |
