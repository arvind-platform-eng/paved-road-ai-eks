terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.32"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "paved-road-ai-eks"
      Environment = "dev"
      ManagedBy   = "terraform"
      Owner       = "arvind"
    }
  }
}

# -----------------------------------------------------------------------------
# Providers for Kubernetes-side resources
# These depend on the EKS cluster existing — read cluster auth data lazily.
# -----------------------------------------------------------------------------
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
}

# -----------------------------------------------------------------------------
# EKS cluster
# -----------------------------------------------------------------------------
module "eks" {
  source = "../../modules/eks-cluster"

  cluster_name       = "paved-road-ai-dev"
  environment        = "dev"
  kubernetes_version = var.kubernetes_version
  availability_zones = var.availability_zones
}

# -----------------------------------------------------------------------------
# Karpenter for GPU autoscaling
# -----------------------------------------------------------------------------
module "karpenter" {
  source = "../../modules/karpenter"

  cluster_name = module.eks.cluster_name

  depends_on = [module.eks]
}

# -----------------------------------------------------------------------------
# Observability stack
# -----------------------------------------------------------------------------
module "observability" {
  source = "../../modules/observability"

  grafana_admin_password = var.grafana_admin_password

  depends_on = [module.karpenter]
}
