variable "prometheus_stack_version" {
  description = "kube-prometheus-stack Helm chart version"
  type        = string
  default     = "62.6.0"
}

variable "dcgm_exporter_version" {
  description = "NVIDIA DCGM exporter Helm chart version"
  type        = string
  default     = "3.6.0"
}

variable "grafana_admin_password" {
  description = "Grafana admin password (use terraform.tfvars, not committed)"
  type        = string
  sensitive   = true
}
