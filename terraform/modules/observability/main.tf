terraform {
  required_version = ">= 1.9"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

# -----------------------------------------------------------------------------
# kube-prometheus-stack — Prometheus + Grafana + AlertManager + node-exporter
# One helm chart, three critical observability tools.
# -----------------------------------------------------------------------------
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.prometheus_stack_version
  namespace        = "monitoring"
  create_namespace = true

    values = [
    yamlencode({
      # Tolerate the system taint so Prometheus can run on system nodes
      # when no workload nodes exist (fresh cluster scenario)
      grafana = {
        adminPassword = var.grafana_admin_password
        persistence = {
          enabled = true
          size    = "10Gi"
        }
        tolerations = [{
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }]
      }

      prometheus = {
        prometheusSpec = {
          retention = "15d"
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                accessModes = ["ReadWriteOnce"]
                resources   = { requests = { storage = "50Gi" } }
              }
            }
          }
          serviceMonitorSelectorNilUsesHelmValues = false
          podMonitorSelectorNilUsesHelmValues     = false
          tolerations = [{
            key      = "CriticalAddonsOnly"
            operator = "Exists"
            effect   = "NoSchedule"
          }]
        }
      }

      alertmanager = {
        alertmanagerSpec = {
          storage = {
            volumeClaimTemplate = {
              spec = {
                accessModes = ["ReadWriteOnce"]
                resources   = { requests = { storage = "5Gi" } }
              }
            }
          }
          tolerations = [{
            key      = "CriticalAddonsOnly"
            operator = "Exists"
            effect   = "NoSchedule"
          }]
        }
      }

      # Operator itself and its admission webhook jobs — these are what's failing
      prometheusOperator = {
        tolerations = [{
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }]
        admissionWebhooks = {
          patch = {
            tolerations = [{
              key      = "CriticalAddonsOnly"
              operator = "Exists"
              effect   = "NoSchedule"
            }]
          }
        }
      }

      # kube-state-metrics and node-exporter also need to run
      kube-state-metrics = {
        tolerations = [{
          key      = "CriticalAddonsOnly"
          operator = "Exists"
          effect   = "NoSchedule"
        }]
      }

      prometheus-node-exporter = {
        tolerations = [{
          operator = "Exists"
        }]
      }
    })
  ]
}

# -----------------------------------------------------------------------------
# DCGM exporter — surfaces GPU utilisation to Prometheus
# Deployed as DaemonSet on GPU nodes only.
# -----------------------------------------------------------------------------
resource "helm_release" "dcgm_exporter" {
  name             = "dcgm-exporter"
  repository       = "https://nvidia.github.io/dcgm-exporter/helm-charts"
  chart            = "dcgm-exporter"
  version          = var.dcgm_exporter_version
  namespace        = "monitoring"

  values = [
    yamlencode({
      serviceMonitor = { enabled = true }
      tolerations = [{
        key      = "nvidia.com/gpu"
        operator = "Exists"
        effect   = "NoSchedule"
      }]
      nodeSelector = {
        "workload-type" = "gpu"
      }
    })
  ]

  depends_on = [helm_release.kube_prometheus_stack]
}
