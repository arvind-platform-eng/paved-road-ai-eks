# Jenkins Pipeline Setup

Setup guide for running the `paved-road-ai-eks` pipeline on your local Jenkins.

## Required Jenkins plugins

Install these via **Manage Jenkins → Plugins**:

| Plugin | Why |
|--------|-----|
| Pipeline | Declarative pipeline syntax |
| Git | Clone the repo |
| Credentials Binding | `withCredentials` support |
| AnsiColor | Coloured terminal output in build logs |
| Timestamper | Timestamps on log lines |
| Workspace Cleanup | `cleanWs` post-action |

Optional but recommended:

| Plugin | Why |
|--------|-----|
| Blue Ocean | Better UI for pipeline visualisation |
| Pipeline: Stage View | Visual stage timeline |

## Required tools on Jenkins agent

The pipeline calls these binaries directly. If Jenkins runs on your host, install them there:

```bash
# macOS
brew install terraform kubectl awscli helm jq

# Linux (Ubuntu/Debian)
sudo apt install -y curl unzip jq
# Terraform
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform
# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install
# Helm
curl -fsSL https://baltocdn.com/helm/signing.asc | sudo gpg --dearmor -o /usr/share/keyrings/helm.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt update && sudo apt install -y helm
```

Optional linters used in Static Analysis stage:

```bash
# tflint
curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
# trivy
sudo apt install -y wget apt-transport-https gnupg
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" | sudo tee /etc/apt/sources.list.d/trivy.list
sudo apt update && sudo apt install -y trivy
```

## Required Jenkins credentials

Go to **Manage Jenkins → Credentials → System → Global credentials → Add credentials**.

### 1. AWS credentials

- **Kind**: Username with password
- **ID**: `aws-credentials` (must match exactly)
- **Username**: your AWS Access Key ID (e.g., `AKIA...`)
- **Password**: your AWS Secret Access Key
- **Description**: `AWS access key for paved-road-ai-eks`

*Security note: for real production, use OIDC federation instead of static keys. Static keys are fine for a local dev setup.*

### 2. Grafana admin password

- **Kind**: Secret text
- **ID**: `grafana-admin-password`
- **Secret**: a strong password of your choice (save it — you'll need it to log in later)
- **Description**: `Grafana admin password for paved-road-ai-eks`

### 3. HuggingFace token

- **Kind**: Secret text
- **ID**: `huggingface-token`
- **Secret**: your HuggingFace access token from https://huggingface.co/settings/tokens
- **Description**: `HuggingFace token for gated model access`

*This is needed because Mistral 7B Instruct is a gated model — HuggingFace requires you to accept terms before downloading.*

## Creating the pipeline job

1. Jenkins home → **New Item**
2. Name: `paved-road-ai-eks`
3. Type: **Pipeline**
4. Under **Pipeline** section:
   - Definition: **Pipeline script from SCM**
   - SCM: **Git**
   - Repository URL: `git@github.com:arvind-platform-eng/paved-road-ai-eks.git`
   - Credentials: add your SSH key if the repo is private, leave blank if public
   - Branch: `*/main`
   - Script Path: `Jenkinsfile`
5. Save.

## Running the pipeline

### First run — always plan first

1. Click **Build with Parameters**
2. Action: `plan`
3. Environment: `dev`
4. Auto-approve: unchecked
5. Deploy workloads: unchecked (just infra for now)
6. Run smoke tests: unchecked
7. Click Build

Review the plan output in build artifacts (`tfplan.txt`) before proceeding.

### First deploy

1. Build with Parameters
2. Action: `apply`
3. Environment: `dev`
4. Auto-approve: unchecked (require manual gate)
5. Deploy workloads: checked
6. Run smoke tests: checked
7. Click Build

The pipeline will pause at the Approval stage. Review the plan, then approve to proceed.

### Destroy

1. Build with Parameters
2. Action: `destroy`
3. Environment: `dev`
4. Click Build, approve at the gate

**Always destroy at the end of each work session to control cost.**

## Troubleshooting

### "Command not found" errors

The Jenkins agent doesn't have the tool installed. Install it on the agent (see tools section above) or switch to a Docker agent per stage.

### AWS credentials errors

- Check the credential ID in Jenkins matches `aws-credentials` exactly (case-sensitive)
- Verify the access key has permissions to create EKS, EC2, VPC, IAM resources
- If you use MFA, static keys won't work — you'll need to configure OIDC or use session tokens

### Pipeline hangs at "Waiting for KServe"

KServe takes time to install (5–8 min typically). The pipeline waits up to 10 min. If it times out:
- Check Argo CD sync status: `kubectl get applications -n argocd`
- Check platform components: `kubectl get pods -A | grep -v Running`

### Terraform state locking issues

If a previous run failed mid-apply, state may be locked:
```bash
cd terraform/envs/dev
terraform force-unlock <LOCK_ID>
```

Only do this if you're certain no other Terraform is running.