# Engineering Journal — paved-road-ai-eks

A running log of issues encountered, debugging steps taken, and lessons learned while building the reference architecture. Written for two audiences: my future self (so I don't repeat mistakes) and interviewers (so they can see how I think through problems).

**How to use this journal:**
- Log every non-trivial error you hit — even small ones
- Follow the same template for each entry (context → symptom → hypothesis → fix → lesson)
- Never edit past entries to look smarter after the fact — the messy debugging is the point
- Reference this file from the main README under "What I learned building this"

**Entry format:**

Each entry has 6 sections. Keep them short — 2-3 sentences each is usually enough.

```
## YYYY-MM-DD — Short title
**Context:** What were you trying to do?
**Symptom:** What went wrong (exact error message if possible)?
**Hypothesis:** What did you think was wrong initially?
**Root cause:** What was actually wrong?
**Fix:** What resolved it (exact commands or config change)?
**Lesson:** What will you do differently next time?
```

---

## 2026-08-24 — HuggingFace token validation returns misleading auth error

**Context:** Setting up HuggingFace authentication for Week 4 — needed to verify the token could download Mistral 7B model weights before deploying the InferenceService. Ran the standard `curl /api/whoami` test that most tutorials suggest.

**Symptom:** `{"error":"Invalid username or password."}` returned for every token attempt, even freshly generated tokens with correct Read permissions. Same error returned when the endpoint was called with no authorization header at all — a hint that the endpoint itself might be the problem, not the credential.

**Hypothesis:** Initial guesses (all wrong):
1. Token was truncated during copy-paste
2. Token had insufficient scoping (fine-grained token issue)
3. Model access hadn't been granted yet

Spent ~30 minutes revoking and regenerating tokens before running a proper diagnostic — testing the endpoint with no auth at all. Same error appeared, which proved the endpoint wasn't validating credentials properly for either case.

**Root cause:** The `/api/whoami` endpoint is deprecated on HuggingFace and returns the same generic "Invalid username or password" message regardless of what token you send it. It's misleading — the error suggests a credential problem when it's actually an endpoint problem.

**Fix:** Switched to testing against the actual resource endpoint that KServe uses in production:

```bash
curl -sL -o /dev/null -w "HTTP status: %{http_code}\n" \
  https://huggingface.co/mistralai/Mistral-7B-Instruct-v0.3/resolve/main/config.json \
  -H "Authorization: Bearer $HF_TOKEN"
```

Also verified with the current API endpoint: `/api/whoami-v2` (note the `-v2` suffix). Both returned HTTP 200 with correct JSON response — confirming the token was valid all along.

**Lesson:** Generic error messages hide real failures. When debugging authentication issues, test against the exact endpoint your production code will hit — not against generic "check my credentials" endpoints. Those endpoints often lag behind API changes and give false negatives. Also: when a fresh token fails the same way as an old token, stop regenerating credentials and check whether the endpoint itself has changed.

---

## Template for future entries

Copy this block for each new issue.

```
## YYYY-MM-DD — [Short title]

**Context:** [What were you doing? What phase of the project?]

**Symptom:** [Exact error message. Copy-paste it. Include the command that produced it.]

**Hypothesis:** [What did you think was wrong initially? Include your first attempts even if they were wrong — the wrong hypotheses are useful debugging material.]

**Root cause:** [What was actually wrong. Be specific — not "network issue" but "kube-proxy pod on node ip-10-0-1-x had OOMKilled state due to insufficient memory request."]

**Fix:** [Exact commands, config changes, or PRs that resolved it. Someone reading this in 3 months should be able to reproduce the fix.]

**Lesson:** [What will you do differently? What signal will you look for earlier next time?]
```

---

## Categories to log — don't skip these

Every project has predictable categories of pain. Log every instance:

- **Authentication & tokens** — HF, AWS IAM, ArgoCD, Kubernetes ServiceAccounts
- **Networking** — VPC CIDR issues, security groups, IPv6, kube-proxy
- **Karpenter provisioning** — instance type not available, spot interruption handling, taints/tolerations mismatch
- **GPU workloads** — CUDA errors, driver mismatches, OOMKilled with GPU pods, model loading timeouts
- **KServe / vLLM** — model download failures, InferenceService stuck in unknown state, autoscaling misbehavior
- **ArgoCD sync issues** — OutOfSync loops, resource conflicts, RBAC on Applications
- **Terraform state** — provider version conflicts, moved/removed blocks, drift detection
- **Cost surprises** — unexpected NAT charges, GPU node forgotten running, data transfer between AZs
- **Helm chart quirks** — CRD ordering, values structure changes between versions
- **Observability gaps** — ServiceMonitor not scraped, dashboards showing gaps, alerts not firing

---

## Interview-worthy stories to develop

As you accumulate entries, some will be interview-worthy — the ones with genuine surprise, non-obvious root cause, and a lesson that transfers to any senior role.

Mark those with `⭐ INTERVIEW` at the top and revisit them before technical rounds. Common patterns interviewers ask about:

- "Walk me through your most memorable debugging session"
- "Tell me about a time a fresh-looking setup broke unexpectedly"
- "Describe a time when the error message misled you"
- "What's an operational lesson you learned the hard way?"

The HF token entry above already fits the "misleading error message" pattern — that's a 5-minute story with a clear lesson. Rehearse it out loud once, and it becomes an easy answer for interview rounds.

---

## Notes for the README

Once this journal has 8–10 entries, extract the top 3 into the main README's "What I learned building this" section — but keep them short and punchy there. The full detail lives here in the journal.

Example README bullet from the HF entry above:
> **HuggingFace `/api/whoami` returns misleading auth errors** — the endpoint is deprecated but still exists. Test against the actual resource endpoint your code will use, not against generic auth check endpoints.

That single line, expanded from the full journal entry, tells a hiring manager everything they need to know about your engineering discipline.


## 2026-10-09 — Fresh terraform apply fails: "Kubernetes cluster unreachable"

**Context:** Running first `terraform apply` on fresh EKS cluster from scratch. Expected single-shot apply to work.

**Symptom:**
Error: Kubernetes cluster unreachable: the server has asked for the client
to provide credentials

with module.observability.helm_release.kube_prometheus_stack,
on ../../modules/observability/main.tf line 19, in resource “helm_release”:


**Hypothesis:** Thought the AWS credentials expired or kubeconfig was wrong.

**Root cause:** Terraform's helm_release provider evaluates authentication at plan time, before the EKS cluster exists. The auth token it tries to use is invalid by the time it attempts the Helm install (~10 minutes later). This is a well-known Terraform + EKS + Helm provider timing issue.

**Fix:** Multi-phase apply pattern. Instead of one `terraform apply`, split into:
```bash
terraform apply -target=module.eks       # phase 1: cluster + addons (~15 min)
./scripts/bootstrap-storage.sh           # phase 2: StorageClass (~5 sec)
terraform apply                          # phase 3: everything else (~10 min)
```

Second `terraform apply` succeeds because the auth token gets freshly generated with the cluster already in place.

**Lesson:** When Terraform providers (helm, kubernetes) depend on resources being created in the same plan, there's an inherent timing problem. The provider configuration is resolved at plan time, but the resource it needs doesn't exist until mid-apply. Single-shot apply is unreliable for fresh clusters — document multi-phase as the standard workflow. Interviewers familiar with EKS know this gotcha instantly.

---

## 2026-10-09 — Helm release "cannot re-use a name that is still in use"

**Context:** After the previous failed apply, re-ran terraform apply.

**Symptom:**
Error: cannot re-use a name that is still in use
with module.observability.helm_release.kube_prometheus_stack


**Hypothesis:** First thought it meant the namespace existed. Deleted the namespace, same error.

**Root cause:** Helm stores release metadata as Kubernetes Secrets in the release's namespace. When Helm install fails midway (as it did due to the auth error), the release metadata secret can still exist. Next install sees the existing release name and refuses to overwrite. Terraform doesn't automatically clean this up on failure — becomes orphan state.

**Fix:**
```bash
# Delete the orphan release secret
kubectl delete namespace monitoring --wait=false --ignore-not-found

# Remove the failed release from Terraform state
cd terraform/envs/dev
terraform state rm module.observability.helm_release.kube_prometheus_stack

# Retry
terraform apply
```

**Lesson:** Terraform + Helm failures leave orphan Kubernetes state. Standard recovery pattern: delete namespace → `terraform state rm` → re-apply. Added this to runbook as universal recovery procedure. Helm's release-tracking secrets are often invisible until they bite you.

---

## 2026-10-09 — kubernetes_storage_class_v1 fails with "Unauthorized"

**Context:** Added gp3 StorageClass to Terraform as `kubernetes_storage_class_v1` in the eks-cluster module (file: `terraform/modules/eks-cluster/storage.tf`).

**Symptom:**
Error: Unauthorized
with module.eks.kubernetes_storage_class_v1.gp3_default


**Hypothesis:** Thought the kubernetes provider was misconfigured in envs/dev.

**Root cause:** The eks-cluster module's `required_providers` block only declares `aws`, not `kubernetes`. The kubernetes provider configured at envs/dev level is NOT automatically available inside child modules — it must be explicitly declared in the module's `required_providers` AND passed via `providers = { kubernetes = kubernetes }` in the module block.

**Fix:** Rather than add cross-provider wiring complexity for a 10-line manifest, replaced with `scripts/bootstrap-storage.sh` — runs `kubectl apply` after terraform completes. Idempotent, documented in runbook.

```bash
rm terraform/modules/eks-cluster/storage.tf
# Created scripts/bootstrap-storage.sh with gp3 StorageClass manifest
chmod +x scripts/bootstrap-storage.sh
```

**Lesson:** Cross-provider wiring in Terraform modules has real complexity. For simple one-off resources (StorageClass, ConfigMap, Secret), a post-apply kubectl script is often cleaner than wiring kubernetes provider through modules. Choose purity (full IaC) vs pragmatism (shell script) based on how often the resource changes. StorageClass changes maybe once a year — script wins.

---

## 2026-10-09 — "context deadline exceeded" on kube-prometheus-stack install

**Context:** terraform apply during fresh cluster deploy.

**Symptom:**
Error: context deadline exceeded
with module.observability.helm_release.kube_prometheus_stack


Pods were visible in the cluster still coming up — install was progressing but Terraform gave up.

**Hypothesis:** Thought the install was broken.

**Root cause:** Default Helm release timeout is 300 seconds (5 min). Fresh EKS clusters need ~10 minutes for the kube-prometheus-stack install because EBS volume provisioning for 3 PVCs (prometheus 50GB, alertmanager 5GB, grafana 10GB) is sequential and slow. The install was actually succeeding — Terraform just timed out before pods became ready.

**Fix:** Added `timeout = 900` to the helm_release resource:
```hcl
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  ...
  timeout          = 900    # 15 min for fresh deploys
  wait             = true
  ...
}
```

**Lesson:** Terraform/Helm default timeouts assume fast provisioning. Cloud resources (EBS volumes, GPU nodes, S3 buckets) are often slow. When wait=true is enabled, always set explicit timeouts based on actual observed provisioning time + 50% buffer. Default 300s is a trap for cloud workloads.

---

## 2026-10-09 — PVCs stuck Pending with STORAGECLASS=<unset>

**Context:** After observability stack installed, Prometheus/Grafana/Alertmanager pods stayed Pending.

**Symptom:**

kubectl get pvc -n monitoring
NAME STATUS STORAGECLASS AGE
...-prometheus-0 Pending <unset> 10m
...-alertmanager-0 Pending <unset> 10m
...-grafana Pending <unset> 10m

kubectl describe pod ...-prometheus-0 -n monitoring:
Warning FailedScheduling default-scheduler
0/2 nodes are available: pod has unbound immediate PersistentVolumeClaims


**Hypothesis:** Thought EBS CSI driver was broken.

**Root cause:** EBS CSI driver was running fine (6/6 Ready). But fresh EKS clusters ship with NO default StorageClass. PVCs that don't explicitly specify `storageClassName` (which is most Helm charts, including kube-prometheus-stack) are ignored by Kubernetes because it doesn't know what provisioner to use. The STORAGECLASS=<unset> in the output was the smoking gun.

**Fix:** Created gp3 StorageClass annotated as default:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
...
```

Then had to delete and recreate the stuck PVCs (they won't auto-adopt the new default):
```bash
kubectl delete pvc -n monitoring --all
kubectl delete pods -n monitoring --field-selector=status.phase=Pending
```

**Lesson:** EBS CSI driver installed ≠ dynamic provisioning working. Need BOTH: (1) CSI driver running with proper IRSA, AND (2) a default StorageClass pointing at it. On fresh EKS, both are missing by default. Always set up both as part of base cluster bootstrap. STORAGECLASS=<unset> is the diagnostic signal — look for it first.

---

## 2026-10-09 — IAM trust policy for EBS CSI had unexpanded shell variables

**Context:** EBS CSI controller pods in CrashLoopBackOff. Needed to create IAM role for IRSA authentication.

**Symptom:**
Pod logs showed:
STS: AssumeRoleWithWebIdentity
StatusCode: 403
api error AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity

**Hypothesis:** Thought the role didn't have the right permissions attached.

**Root cause:** Created the trust policy via a heredoc with nested shell command substitutions like `$(aws eks describe-cluster --query 'cluster.identity.oidc.issuer')`. On Windows Git Bash, those nested substitutions didn't expand correctly inside the heredoc, leaving literal placeholder text in the uploaded trust policy. The federated principal and OIDC conditions were therefore invalid JSON — no ServiceAccount could ever assume the role.

**Fix:** Two-stage variable expansion — set shell variables with simple commands first, then reference them in the heredoc:
```bash
OIDC_URL=$(aws eks describe-cluster --name paved-road-ai-dev --region us-east-1 \
  --query 'cluster.identity.oidc.issuer' --output text | sed 's|https://||')
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

cat > ~/ebs-trust.json <<EOF
{
  "Version": "2012-10-17",
  ...
  "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_URL}"
  ...
}
EOF

# Verify real values made it into the file BEFORE uploading
cat ~/ebs-trust.json
```

Also hit a related issue: AWS CLI on Windows didn't understand `/tmp/` paths. Had to use `~/ebs-trust.json` with `cygpath -w` conversion:
```bash
aws iam update-assume-role-policy \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --policy-document "file://$(cygpath -w ~/ebs-trust.json)"
```

**Lesson:** When writing JSON policies with shell command substitution, always verify the resulting file contains real values before using it. Nested `$()` in heredocs is fragile on Windows. Two-stage approach — compute values first, then interpolate — is more reliable. Also: AWS CLI on Windows wants Windows paths. Use `cygpath -w` or `file://C:/Users/.../file.json` with forward slashes. Cross-platform tooling has these quirks — testing on Linux never exposes them.