# CI/CD strategy

This project uses two CI/CD systems with a deliberate separation of duties.

## GitHub Actions — validation

**File:** `.github/workflows/ci.yml`
**Trigger:** Every push and pull request
**Duration:** ~2 minutes
**Credentials:** None

Runs cheap, safe, fast checks on every commit:

- Terraform `fmt` and `validate`
- TFLint best-practice linting
- Trivy security scan on Terraform configs
- Kustomize build validation
- YAML lint

The goal is a green tick on every commit. If any check fails, the pull request is blocked from merge. No AWS credentials are involved, so this runs on public GitHub runners at zero cost.

## Jenkins — deployment

**File:** `Jenkinsfile`
**Trigger:** Manual (via Jenkins UI) or approved merge to `main`
**Duration:** 30–45 minutes for a full apply
**Credentials:** AWS access key, Grafana password, HuggingFace token

Runs the expensive, credentialed, stateful operations:

- Full Terraform lifecycle (plan / apply / destroy)
- ArgoCD bootstrap on the newly-created cluster
- Mistral 7B workload deploy
- Inference smoke test
- Diagnostic capture on failure

The goal is safe, auditable deployment to a real AWS environment. Every apply is gated by manual approval and archives its plan as a build artifact.

## Why both

The two systems solve different problems.

**GitHub Actions catches mistakes early.** A developer pushing a broken Terraform config gets a red X on their commit within 2 minutes. They fix it locally before opening a pull request. The cost is zero and the feedback loop is short.

**Jenkins gates real infrastructure changes.** No commit can create AWS resources by itself — it must be explicitly triggered through Jenkins with human approval. This is auditable, reversible, and keeps AWS credentials out of the source code hosting platform entirely.

The two systems overlap slightly: Jenkins re-runs the same static analysis GitHub Actions runs. That's deliberate. Jenkins should trust nothing — if the developer's local environment or a merge race introduced a regression, Jenkins catches it before spending time on infrastructure.

## What NOT to do

**Don't put AWS credentials in GitHub Actions.** GitHub secrets work, but they widen the attack surface — anyone with write access to the repo can potentially exfiltrate them via a malicious workflow. Real deployments belong in a system you control.

**Don't skip GitHub Actions and use only Jenkins.** Pull request reviews benefit from automated checks that show up in the PR conversation. Without GitHub Actions, reviewers must manually verify style and syntax, or wait for Jenkins to run.

**Don't run both on the same trigger.** GitHub Actions on every push; Jenkins on explicit intent. Running both automatically on every commit doubles cost and confuses the responsibility model.