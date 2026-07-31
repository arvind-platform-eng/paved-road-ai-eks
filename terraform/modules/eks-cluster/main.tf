terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

locals {
  common_tags = merge(var.tags, {
    Module      = "eks-cluster"
    ManagedBy   = "terraform"
    Environment = var.environment
  })
}

# -----------------------------------------------------------------------------
# VPC for the EKS cluster
# Two AZs, public + private subnets, single NAT for cost savings in dev.
# -----------------------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  public_subnets  = var.public_subnet_cidrs
  private_subnets = var.private_subnet_cidrs

  enable_nat_gateway   = true
  single_nat_gateway   = var.environment == "prod" ? false : true
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb"                        = "1"
    "kubernetes.io/cluster/${var.cluster_name}"     = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"               = "1"
    "kubernetes.io/cluster/${var.cluster_name}"     = "shared"
    "karpenter.sh/discovery"                        = var.cluster_name
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# EKS cluster with a small managed node group for platform components.
# GPU nodes come later via Karpenter — not here.
# -----------------------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  # Enable IRSA and Pod Identity (both — Karpenter uses Pod Identity)
  enable_irsa                              = true
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
  }

  # Small system node group for cluster-critical workloads (CoreDNS, Karpenter itself)
  eks_managed_node_groups = {
    system = {
      name           = "system-ng"
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 3
      desired_size   = 2

      labels = {
        workload = "system"
      }

      taints = {
        system = {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  # Discovery tag for Karpenter
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  tags = local.common_tags
}
