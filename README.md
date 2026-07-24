# Paved Road for AI Workloads on EKS

> A reference architecture for running large language model inference on Amazon EKS — with GPU autoscaling, GitOps delivery, and production-grade observability. Built so any team can go from `git push` to a live model endpoint in under 30 minutes.

![Build](https://img.shields.io/github/actions/workflow/status/arvind-platform-eng/paved-road-ai-eks/ci.yml?branch=main)
![License](https://img.shields.io/github/license/arvind-platform-eng/paved-road-ai-eks)
![Terraform](https://img.shields.io/badge/terraform-1.9+-purple)
![Kubernetes](https://img.shields.io/badge/kubernetes-1.30+-blue)
![vLLM](https://img.shields.io/badge/vLLM-0.6+-green)

---

## Why this exists

Most Platform Engineers can run stateless web services on Kubernetes. Very few have production experience running GPU-backed LLM inference at scale. The gap between "I know Kubernetes" and "I can serve a 7B parameter model with sub-second latency and 60% cost savings" is where AI infrastructure roles are hiring right now.

This repo is that gap, closed. It's a working reference architecture that any engineering team can fork and deploy — with the design decisions, cost analysis, and operational runbooks that turn a Kubernetes deployment into a real production platform.

## What it does

- Provisions a production-ready EKS cluster with Karpenter managing spot GPU nodes on demand
- Serves an open-weight LLM (Mistral 7B by default, swappable) through vLLM's high-throughput inference engine
- Routes traffic through KServe InferenceService for versioning and canary deployments
- Delivers everything through ArgoCD with an ApplicationSet — no manual `kubectl apply`
- Exposes GPU utilisation, token throughput, and request latency (p50/p95/p99) through Prometheus and Grafana
- Autoscales based on request queue depth using KEDA, not just CPU

## Architecture

![Architecture diagram](docs/architecture.png)

The system has four layers:

- **Infrastructure** — Terraform provisions EKS, VPC, IAM, and node groups. Karpenter takes over node lifecycle after bootstrap.
- **GitOps control plane** — ArgoCD reconciles all cluster state from this repo. The `apps/` directory is the source of truth.
- **Inference layer** — vLLM runs inside KServe InferenceServices with GPU node selectors and pod disruption budgets.
- **Observability** — Prometheus scrapes vLLM metrics, DCGM exporter surfaces GPU utilisation, Grafana renders it all.

## Quick start

### Prerequisites

- AWS account with GPU quota (request `g5.xlarge` limit >= 4 in your target region)
- Terraform >= 1.9
- kubectl >= 1.30
- Helm 3.x
- AWS CLI configured with credentials that can create EKS, IAM, and VPC resources

### Deploy in ~30 minutes

```bash
# Clone the repo
git clone git@github.com:arvind-platform-eng/paved-road-ai-eks.git
cd paved-road-ai-eks

# Provision the EKS cluster (~15 min)
cd terraform/envs/dev
terraform init
terraform apply

# Configure kubectl
aws eks update-kubeconfig --name paved-road-ai-dev --region us-east-1

# Bootstrap ArgoCD (~2 min)
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Deploy the platform stack (Karpenter, KServe, vLLM, monitoring)
kubectl apply -f apps/bootstrap/

# Wait for GPU node to provision (~5 min after first inference request)
kubectl get nodes -w

# Send your first inference request
kubectl port-forward svc/mistral-7b-predictor 8080:80 -n inference
curl -X POST http://localhost:8080/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "mistral-7b", "prompt": "The future of platform engineering is", "max_tokens": 100}'
```

## Design decisions

The interesting choices behind this architecture — trade-offs, not defaults.

- **Why vLLM over Text Generation Inference (TGI) or Triton** — vLLM's PagedAttention gives 2–4x higher throughput at the same GPU cost. TGI is easier to run but slower. Triton is more general-purpose but requires more configuration for LLM-specific optimisations.
- **Why KServe over raw Deployments** — KServe abstracts model versioning, canary rollouts, and autoscaling into a single CRD. A Deployment works, but every team ends up rebuilding these concerns.
- **Why Karpenter over Cluster Autoscaler** — Karpenter provisions nodes in ~40 seconds vs. Cluster Autoscaler's ~2 minutes. For GPU workloads where each cold start is expensive, this matters. It also handles spot/on-demand mixing natively.
- **Why spot GPUs by default** — g5.xlarge spot pricing is ~65% cheaper than on-demand. For inference (not training), interruption tolerance is manageable — KServe pod disruption budgets handle graceful drain.
- **Why an ApplicationSet, not individual ArgoCD Applications** — one YAML defines all environment variants (dev/staging/prod). Reduces GitOps drift, single source of truth.
- **Why the model comes from S3 at startup, not baked into the container** — model weights are 4–14GB. Baking them into images makes them slow to build, slow to pull, and impossible to swap without a redeploy. S3 storage-initializer is the standard KServe pattern.

## Repository structure

```
.
├── terraform/                # Infrastructure as code
│   ├── modules/
│   │   ├── eks-cluster/     # EKS cluster module
│   │   ├── karpenter/       # Karpenter installation
│   │   └── observability/   # Prometheus/Grafana stack
│   └── envs/
│       ├── dev/
│       └── prod/
├── kubernetes/
│   ├── base/                # Kustomize base manifests
│   └── overlays/            # Environment-specific overlays
├── apps/                    # ArgoCD ApplicationSet definitions
│   ├── bootstrap/
│   ├── platform/            # Karpenter, KServe, monitoring
│   └── workloads/           # Model deployments
├── charts/                  # Custom Helm charts
├── scripts/                 # Utility scripts (load testing, model download)
├── docs/
│   ├── architecture.png
│   ├── cost-analysis.md    # Detailed cost breakdown
│   ├── runbook.md          # Operational runbook
│   └── ADRs/               # Architecture Decision Records
├── .github/workflows/
│   └── ci.yml              # Terraform validate, kubeval, tflint
└── README.md
```

## Cost analysis

Running this reference architecture in `dev` mode (single g5.xlarge spot GPU node, minimal control plane):

| Component | Monthly cost |
|-----------|-------------:|
| EKS control plane | ~$73 |
| GPU node (g5.xlarge spot, ~8 hrs/day) | ~$32 |
| S3 model storage | ~$1 |
| Data transfer | ~$3 |
| **Total** | **~$109/month** |

For interview conversations, the key point is not the absolute cost — it's the *savings* achieved by design choices: spot GPUs (65% off), Karpenter consolidation (nodes only up when needed), and shared control plane (one cluster serves many models).

Full breakdown with production sizing in [docs/cost-analysis.md](docs/cost-analysis.md).

## What I learned building this

- **GPU pods don't drain gracefully by default** — vLLM holds model weights in VRAM. Setting `terminationGracePeriodSeconds: 300` and adding a preStop hook that drains the request queue was essential.
- **Karpenter spot interruption on GPUs is more disruptive than CPU** — a 2-minute warning isn't enough to move a live inference workload. Solution: over-provision by 1 replica and use PodDisruptionBudgets.
- **Prometheus scraping vLLM metrics needed a ServiceMonitor, not annotations** — vLLM exposes rich metrics but doesn't auto-register with Prometheus. Adding a ServiceMonitor CRD unlocks all the throughput dashboards.

## Roadmap

- [ ] Multi-model serving with KServe ModelMesh
- [ ] Prompt caching layer with Redis
- [ ] Cost-per-token dashboard using OpenCost + Prometheus
- [ ] Chaos engineering experiments (GPU node interruption, model loading failure)
- [ ] Terraform module publication to Terraform Registry

## Contributing

Contributions are welcome. Please open an issue first to discuss significant changes.

## License

[MIT](LICENSE) © Arvind Kumar

---

Built by [Arvind Kumar](https://github.com/arvind-platform-eng) — Lead Platform Engineer & SRE.
