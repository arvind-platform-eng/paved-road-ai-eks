# Deploy Guide — paved-road-ai-eks

A reference architecture for AI/LLM workloads on Amazon EKS with Karpenter GPU autoscaling, KServe, vLLM, and ArgoCD GitOps.

---

## ⚠️ CRITICAL — Read this first

**NEVER run a single-shot `terraform apply` on a fresh cluster.** It fails reliably with:
Error: Kubernetes cluster unreachable: the server has asked for the
client to provide credentials


**Why:** Terraform's Helm/Kubernetes providers pre-compute auth tokens at plan time, before the EKS cluster exists. By the time Helm installs run (~15 min later), the token is stale.

**Always use the phased sequence below. No exceptions.**

---

## Prerequisites

Before your first deploy, make sure you have:

- [ ] AWS account with G-family GPU quota approved (8 vCPUs on-demand + 8 vCPUs spot in us-east-1)
- [ ] AWS CLI configured (`aws sts get-caller-identity` returns your account)
- [ ] Terraform 1.9+ installed (`terraform version`)
- [ ] kubectl installed (`kubectl version --client`)
- [ ] HuggingFace account + Mistral 7B model access + Read token saved to password manager
- [ ] `terraform/envs/dev/terraform.tfvars` created from the example with your Grafana password

```bash
# One-time setup if tfvars not yet created
cd terraform/envs/dev
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set grafana_admin_password to a strong password
# Save password to password manager under "Grafana — paved-road-ai-eks"
```

---

## Full deploy sequence (~35-40 min from clean slate)

### Phase 1 — EKS cluster + addons (~15 min)

Installs: VPC, subnets, NAT, EKS control plane, system node group, cluster addons (coredns, kube-proxy, vpc-cni, eks-pod-identity-agent, aws-ebs-csi-driver), IAM roles.

```bash
cd terraform/envs/dev
terraform init
terraform apply -target=module.eks
# type: yes
```

**Verify before continuing:**

```bash
# Point kubectl at the new cluster
aws eks update-kubeconfig --name paved-road-ai-dev --region us-east-1

# Should return 2 Ready nodes
kubectl get nodes

# EBS CSI should be running (6/6 controller, 3/3 node pods)
kubectl get pods -n kube-system | grep ebs-csi
```

---

### Phase 2 — Default StorageClass (~5 sec)

Fresh EKS clusters have no default StorageClass. PVCs without explicit `storageClassName` sit Pending forever. This script creates gp3 as the default.

```bash
cd /d/Project/paved-road-ai-eks
./scripts/bootstrap-storage.sh
```

**Verify:**

```bash
kubectl get storageclass
# Expected: gp3 (default)   ebs.csi.aws.com   Delete   WaitForFirstConsumer   true
```

---

### Phase 3 — Full stack: Karpenter + observability (~10 min)

Installs Karpenter (GPU autoscaling), kube-prometheus-stack (Prometheus + Grafana + Alertmanager).

```bash
cd terraform/envs/dev
terraform apply
# type: yes
```

**Verify:**

```bash
# All pods should be Running
kubectl get pods -A | grep -v Running | grep -v Completed
# Expected: empty (or just header line)

# PVCs should be Bound
kubectl get pvc -n monitoring
# Expected: 3 PVCs, all Bound to gp3 EBS volumes
```

---

### Phase 4 — ArgoCD GitOps controller (~5 min)

Installs ArgoCD with CriticalAddonsOnly tolerations, ApplicationSet CRD, and prints the initial admin password.

```bash
cd /d/Project/paved-road-ai-eks
./scripts/bootstrap-argocd.sh
```

**Important:** This script prints the initial admin password at the end. **SAVE IT IMMEDIATELY** to your password manager under "ArgoCD admin — paved-road-ai-eks". The secret gets deleted after the first password change.

**Verify:**

```bash
# All 7 ArgoCD pods should be Running
kubectl get pods -n argocd
# Expected: argocd-application-controller-0, argocd-applicationset-controller,
# argocd-dex-server, argocd-notifications-controller, argocd-redis,
# argocd-repo-server, argocd-server — all Running
```

---

### Phase 5 — Apply root Application (GitOps platform sync)

Triggers ArgoCD to read `apps/platform/applicationset.yaml` and generate 4 child Applications (cert-manager, ingress-nginx, knative-serving, kserve).

```bash
kubectl apply -f apps/bootstrap/application.yaml
```

**Watch the sync:**

```bash
kubectl get applications -n argocd -w
```

Wait until all 5 Applications (root + 4 children) show `SYNC=Synced` and `HEALTH=Healthy`. Press Ctrl+C once done. Takes 10-15 min (KServe is slowest — depends on Knative being ready first).

---

## Access the UIs

### Grafana — metrics dashboards

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Open [http://localhost:3000](http://localhost:3000)
Login: `admin` / password from `terraform.tfvars`

Pre-loaded dashboards worth exploring:
- Kubernetes / Compute Resources / Cluster
- Node Exporter / Nodes
- Kubernetes / Compute Resources / Namespace (Pods)

### ArgoCD — GitOps tree view

In a NEW terminal (so port-forward stays running):

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open [https://localhost:8080](https://localhost:8080) (accept the self-signed cert warning)
Login: `admin` / password from `bootstrap-argocd.sh` output

### Prometheus — raw metrics (optional)

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

Open [http://localhost:9090](http://localhost:9090)

---

## Teardown sequence (~10 min)

**Always run at end of session.** Idle cost ≈ ₹15-20/hour.

```bash
# 1. Delete ArgoCD applications first (so Terraform state stays clean)
kubectl delete -f apps/bootstrap/application.yaml 2>/dev/null || true
kubectl delete namespace argocd --wait=false --ignore-not-found

# 2. Standard Terraform destroy
cd terraform/envs/dev
terraform destroy
# type: yes

# 3. Verify completely clean
aws eks describe-cluster --name paved-road-ai-dev --region us-east-1 2>&1 | head -3
# Expected: ResourceNotFoundException
```

Idle cost stops accruing from the moment destroy completes.

---

## Common recovery patterns

### "Kubernetes cluster unreachable" during Helm install

**Cause:** Helm provider got stale auth token (single-shot apply, or re-apply after cluster recreation).

```bash
aws eks update-kubeconfig --name paved-road-ai-dev --region us-east-1
kubectl get nodes

# If kubectl works, Terraform just has stale token — re-run apply
cd terraform/envs/dev
terraform apply
```

### kubectl "no such host" / "dial tcp: lookup ...eks.amazonaws.com"

**Cause:** kubeconfig points at a destroyed cluster's endpoint.

```bash
aws eks update-kubeconfig --name paved-road-ai-dev --region us-east-1
```

### Helm release "cannot re-use a name that is still in use"

**Cause:** Previous failed install left an orphan release metadata secret in the namespace.

```bash
# Replace <ns> with the actual namespace from the error
kubectl delete namespace <ns> --wait=false --ignore-not-found
cd terraform/envs/dev
terraform state rm module.<module>.helm_release.<release>
terraform apply
```

### PVCs stuck Pending with STORAGECLASS=\<unset\>

**Cause:** Default StorageClass not created (Phase 2 skipped).

```bash
./scripts/bootstrap-storage.sh
kubectl delete pvc -n monitoring --all
kubectl delete pods -n monitoring --field-selector=status.phase=Pending
```

### ArgoCD pods Pending (scheduling)

**Cause:** Fresh cluster has only tainted system nodes.

```bash
# bootstrap-argocd.sh is idempotent — just re-run it
./scripts/bootstrap-argocd.sh
```

### EKS addon "cannot be updated — currently in CREATING state"

**Cause:** Terraform tried to modify an addon still being provisioned (async lifecycle).

```bash
# Wait for addon to go ACTIVE
aws eks describe-addon \
  --cluster-name paved-road-ai-dev \
  --region us-east-1 \
  --addon-name aws-ebs-csi-driver \
  --query 'addon.status' --output text
# Repeat every 30s until returns "ACTIVE", then re-run terraform apply
```

### "AMI for Kubernetes version X not supported"

**Cause:** K8s version in Terraform has reached end-of-support on EKS.

Bump version in both files (currently supported: 1.31 — 1.35):

- `terraform/envs/dev/variables.tf`
- `terraform/modules/eks-cluster/variables.tf`

Change `default = "1.XX"` to the current supported version.

### Namespace stuck in Terminating

```bash
kubectl get namespace <ns> -o json | \
  grep -v '"kubernetes"' | \
  kubectl replace --raw "/api/v1/namespaces/<ns>/finalize" -f -
```

---

## Cost estimate

| Component | Hourly cost |
|-----------|-------------|
| EKS control plane | $0.10 (₹8) |
| 2× t3.medium system nodes | $0.083 (₹7) |
| NAT gateway | $0.045 + data (₹4+) |
| EBS volumes (3× in monitoring) | ~$0.01 |
| **Idle total** | **~₹15-20/hour** |

Add ~$1-2/hour when a GPU node is running (g5.xlarge spot).

**Budget ceiling:** ₹2,000/week for this project. If exceeded, review your destroy discipline.

---

## Repo structure quick reference

paved-road-ai-eks/
├── DEPLOY.md ← you are here
├── README.md ← project overview
├── JOURNAL.md ← debugging stories, lessons
├── docs/
│ ├── runbook.md ← expanded recovery patterns
│ ├── architecture.svg
│ ├── cost-analysis.md
│ ├── screenshots/
│ └── ADRs/ ← architecture decisions
├── terraform/
│ ├── envs/dev/ ← dev environment root module
│ └── modules/
│ ├── eks-cluster/ ← cluster + addons + IRSA
│ ├── karpenter/ ← Karpenter + NodePool for GPU
│ └── observability/ ← kube-prometheus-stack
├── apps/
│ ├── bootstrap/application.yaml ← ArgoCD root Application
│ └── platform/applicationset.yaml ← platform component definitions
└── scripts/
├── bootstrap-storage.sh ← Phase 2: default StorageClass
├── bootstrap-argocd.sh ← Phase 4: ArgoCD install
└── load-test.sh ← vLLM load testing


---

## Session discipline — end of every work session

- [ ] Screenshots of anything new in Grafana / ArgoCD → `docs/screenshots/`
- [ ] Commit any Terraform / manifest changes to git
- [ ] Journal debugging stories in `JOURNAL.md`
- [ ] Run full teardown sequence
- [ ] Verify `aws eks describe-cluster` returns `ResourceNotFoundException`
- [ ] Close laptop

Earned from 10+ hours of debugging across 2 days — build the discipline early, or the AWS bill reminds you later.