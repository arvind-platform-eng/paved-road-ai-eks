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
      grafana = {
        adminPassword = var.grafana_admin_password
        persistence = {
          enabled = true
          size    = "10Gi"
        }
        # Preload useful dashboards for GPU + vLLM
        dashboardProviders = {
          "dashboardproviders.yaml" = {
            apiVersion = 1
            providers = [{
              name            = "default"
              orgId           = 1
              folder          = ""
              type            = "file"
              disableDeletion = false
              editable        = true
              options = { path = "/var/lib/grafana/dashboards/default" }
            }]
          }
        }
      }

      prometheus = {
        prometheusSpec = {
          retention = "15d"
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                accessModes = ["ReadWriteOnce"]
                resources = { requests = { storage = "50Gi" } }
              }
            }
          }
          # Scrape all ServiceMonitors in the cluster, not just our namespace
          serviceMonitorSelectorNilUsesHelmValues = false
          podMonitorSelectorNilUsesHelmValues     = false
        }
      }

      alertmanager = {
        alertmanagerSpec = {
          storage = {
            volumeClaimTemplate = {
              spec = {
                accessModes = ["ReadWriteOnce"]
                resources = { requests = { storage = "5Gi" } }
              }
            }
          }
        }
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
