variable "aws_region" {
  description = "AWS region to deploy the cluster into"
  type        = string
  default     = "us-east-1"
}

variable "availability_zones" {
  description = "AZs to use in the region"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.30"
}

variable "grafana_admin_password" {
  description = "Grafana admin password — set in terraform.tfvars, never commit"
  type        = string
  sensitive   = true
}
