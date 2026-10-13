# Tomorrow TODO — from 2026-10-13/14 session

## URGENT (do before Saturday deploy)
1. Revoke 2 exposed HF tokens: https://huggingface.co/settings/tokens
   - [REDACTED - token from Oct 13 screenshot, see password manager history]
   - Whatever token was pasted Oct 13 night
   Generate 1 fresh, save to password manager

## Repo updates needed (from this session's debugging)

### 1. apps/workloads/mistral-7b/inferenceservice.yaml
BUG: args array has orphan "bfloat16" value after "--dtype half".
vLLM uses last value → bfloat16 → T4 GPU (compute 7.5) can't run → crash.

FIX:
- Remove the standalone "bfloat16" line from args
- Change --max-model-len from 8192 to 4096 (fits T4 memory)
- Add --enforce-eager (T4 struggles with CUDA graphs)
- Add startupProbe override:
    startupProbe:
      httpGet:
        path: /health
        port: 8080
      failureThreshold: 90
      periodSeconds: 10
      initialDelaySeconds: 60

### 2. terraform/modules/karpenter/main.tf
MISSING: IAM policy for iam:GetInstanceProfile (lost on every destroy)

ADD:
  resource "aws_iam_role_policy" "karpenter_instance_profile" {
    name = "KarpenterInstanceProfilePermissions"
    role = aws_iam_role.karpenter_controller.name
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = [
          "iam:GetInstanceProfile", "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile", "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile", "iam:TagInstanceProfile",
          "iam:PassRole"
        ]
        Resource = "*"
      }]
    })
  }

### 3. terraform/modules/karpenter/main.tf
MISSING: EKS access entry for Karpenter node role.
Without this, GPU nodes boot but can't register with EKS API → silently rejected.
This was the Oct 12 "GPU boots but doesn't join cluster" root cause.

ADD:
  resource "aws_eks_access_entry" "karpenter_node" {
    cluster_name  = var.cluster_name
    principal_arn = aws_iam_role.karpenter_node.arn
    type          = "EC2_LINUX"
  }

### 4. New script: scripts/bootstrap-ai-stack.sh
Replicates the manual install from this session:
- Patch cert-manager tolerations (already installed by ArgoCD)
- Install Knative Serving CRDs + core (not just operator)
- Install KServe
- Fix KServe image: kube-rbac-proxy → quay.io/brancz/kube-rbac-proxy:v0.14.0
- Patch all tolerations on new namespaces
- Install NVIDIA device plugin:
    kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.17.0/deployments/static/nvidia-device-plugin.yml

### 5. DEPLOY.md
Add Phase 5 "AI stack install" between current Phase 4 (ArgoCD) and Mistral deploy:
  ./scripts/bootstrap-ai-stack.sh

Or add note that direct install bypasses ArgoCD limitation (scaffold's
ApplicationSet installs Knative operator not Knative Serving).

### 6. JOURNAL.md
Add entries for 2026-10-13 (previous session) and 2026-10-13/14 (tonight):

- 2026-10-13: Karpenter 1.0.6 incompatible with K8s 1.35 (bumped to 1.6.0)
- 2026-10-13: EC2 Spot service-linked role missing (one-time account setup)
- 2026-10-13: Karpenter IAM iam:GetInstanceProfile missing
- 2026-10-13: UnfulfillableCapacity AWS GPU exhaustion overnight
- 2026-10-13/14: EKS access entry for Karpenter node role missing (ROOT CAUSE from Oct 12 - instance boots but never joins)
- 2026-10-13/14: NVIDIA device plugin not installed (scaffold gap - without it, nvidia.com/gpu not allocatable even on GPU node)
- 2026-10-13/14: vLLM dtype orphan bfloat16 in manifest - T4 compute 7.5 can't run bfloat16
- 2026-10-13/14: Startup probe killed vLLM before model finished loading

## Saturday session plan
1. Edit mistral manifest (fix #1 above) BEFORE deploying
2. Terraform apply phased deploy
3. Run scripts/bootstrap-ai-stack.sh (fix #4 above - write it Saturday)
4. Create inference namespace + HF secret (with CORRECT token)
5. Deploy Mistral - should work with all fixes

Estimated Saturday time: 90 min clean deploy to first inference.

