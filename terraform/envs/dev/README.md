# dev environment

Deploys the full paved-road stack to a single AWS account for testing and development.

## What gets created

- 1 EKS cluster (`paved-road-ai-dev`) with 2 system nodes
- Karpenter with a GPU spot NodePool ready to scale
- Prometheus, Grafana, AlertManager, DCGM exporter
- VPC with public/private subnets, single NAT for cost

## Estimated cost

Idle (no GPU workloads running): **~$110/month**
- EKS control plane: $73
- 2× t3.medium system nodes: $30
- NAT gateway + data: $5
- EBS volumes (Prometheus + Grafana): $5

Active (1× g5.xlarge spot GPU node, 8 hrs/day): **~$140/month**

## Deploy

```bash
# Copy the example tfvars and fill in your password
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars

# Initialize and apply
terraform init
terraform plan
terraform apply

# ~15 minutes later, configure kubectl
aws eks update-kubeconfig --name paved-road-ai-dev --region us-east-1

# Verify
kubectl get nodes
kubectl get pods -A
```

## Destroy

```bash
# Order matters: workloads → observability → karpenter → eks
kubectl delete inferenceservice --all -A
terraform destroy
```

Do this **before ending your work session**. Idle EKS still costs money.

## Access Grafana

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Open http://localhost:3000
# Username: admin
# Password: whatever you set in terraform.tfvars
```
