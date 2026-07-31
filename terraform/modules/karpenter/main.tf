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
  }
}

locals {
  namespace       = "kube-system"
  service_account = "karpenter"
}

# -----------------------------------------------------------------------------
# IAM role for Karpenter controller (via Pod Identity)
# Karpenter needs to manage EC2 instances, so it needs broad EC2 permissions.
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "karpenter_controller_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  name               = "${var.cluster_name}-karpenter-controller"
  assume_role_policy = data.aws_iam_policy_document.karpenter_controller_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}

resource "aws_eks_pod_identity_association" "karpenter" {
  cluster_name    = var.cluster_name
  namespace       = local.namespace
  service_account = local.service_account
  role_arn        = aws_iam_role.karpenter_controller.arn
}

# Minimal controller policy (production would use terraform-aws-modules/eks/aws//modules/karpenter)
resource "aws_iam_policy" "karpenter_controller" {
  name        = "${var.cluster_name}-karpenter-controller"
  description = "Karpenter controller policy — manages EC2, uses SSM for AMI discovery"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateTags",
          "ec2:DeleteLaunchTemplate",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets",
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "iam:PassRole",
          "pricing:GetProducts",
          "ssm:GetParameter",
          "eks:DescribeCluster"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["sqs:DeleteMessage", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
        Resource = aws_sqs_queue.karpenter_interruption.arn
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Node IAM role — attached to every EC2 instance Karpenter provisions
# -----------------------------------------------------------------------------
resource "aws_iam_role" "karpenter_node" {
  name = "${var.cluster_name}-karpenter-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_ssm" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# -----------------------------------------------------------------------------
# SQS queue for spot interruption notices
# EventBridge -> SQS -> Karpenter reads and gracefully drains nodes
# -----------------------------------------------------------------------------
resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = "${var.cluster_name}-karpenter-interruption"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
  tags                      = var.tags
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = ["events.amazonaws.com", "sqs.amazonaws.com"] }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.karpenter_interruption.arn
    }]
  })
}

# EventBridge rules that forward spot interruption events into the queue
resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name        = "${var.cluster_name}-spot-interruption"
  description = "Route EC2 spot interruption events to Karpenter"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })
}

resource "aws_cloudwatch_event_target" "spot_interruption" {
  rule = aws_cloudwatch_event_rule.spot_interruption.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

# -----------------------------------------------------------------------------
# Karpenter Helm release
# -----------------------------------------------------------------------------
resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_version
  namespace  = local.namespace

  set {
    name  = "settings.clusterName"
    value = var.cluster_name
  }
  set {
    name  = "settings.interruptionQueue"
    value = aws_sqs_queue.karpenter_interruption.name
  }
  set {
    name  = "serviceAccount.name"
    value = local.service_account
  }
  set {
    name  = "controller.resources.requests.cpu"
    value = "500m"
  }
  set {
    name  = "controller.resources.requests.memory"
    value = "512Mi"
  }
  set {
    name  = "tolerations[0].key"
    value = "CriticalAddonsOnly"
  }
  set {
    name  = "tolerations[0].operator"
    value = "Exists"
  }

  depends_on = [
    aws_eks_pod_identity_association.karpenter
  ]
}

# -----------------------------------------------------------------------------
# NodeClass and NodePool for GPU workloads
# -----------------------------------------------------------------------------
resource "kubectl_manifest" "gpu_node_class" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "gpu"
    }
    spec = {
      role      = aws_iam_role.karpenter_node.name
      amiFamily = "AL2023"
      amiSelectorTerms = [{
        alias = "al2023@latest"
      }]
      subnetSelectorTerms = [{
        tags = { "karpenter.sh/discovery" = var.cluster_name }
      }]
      securityGroupSelectorTerms = [{
        tags = { "karpenter.sh/discovery" = var.cluster_name }
      }]
      blockDeviceMappings = [{
        deviceName = "/dev/xvda"
        ebs = {
          volumeSize = "100Gi"
          volumeType = "gp3"
          encrypted  = true
        }
      }]
      tags = merge(var.tags, {
        Name = "${var.cluster_name}-gpu-node"
      })
    }
  })

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "gpu_node_pool" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "gpu-spot"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            "workload-type" = "gpu"
          }
        }
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "gpu"
          }
          taints = [{
            key    = "nvidia.com/gpu"
            value  = "true"
            effect = "NoSchedule"
          }]
          requirements = [
            {
              key      = "karpenter.k8s.aws/instance-family"
              operator = "In"
              values   = ["g5", "g4dn"]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["spot", "on-demand"]
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            }
          ]
          expireAfter = "168h"
        }
      }
      limits = {
        cpu    = "100"
        memory = "400Gi"
      }
      disruption = {
        consolidationPolicy = "WhenEmpty"
        consolidateAfter    = "1m"
      }
    }
  })

  depends_on = [kubectl_manifest.gpu_node_class]
}
