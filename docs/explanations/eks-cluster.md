
# EKS module — a walkthrough

*File: `terraform/modules/eks-cluster/main.tf`*

This is my working explanation of the eks-cluster module. Written in the order I'd say it in an interview or code review — outside layers first, details only on request.

---

## Layer 1 — Purpose

This module provisions a production-ready EKS cluster with networking, a system node group for cluster-critical workloads, and the addons Karpenter will later need.

---

## Layer 2 — Inputs and outputs

It takes a cluster name, environment, Kubernetes version, and availability zones as inputs. It outputs the cluster endpoint, OIDC provider ARN, VPC ID, and private subnet IDs — everything downstream modules like Karpenter need to attach to this cluster.

---

## Layer 3 — The story in five chunks


The file has three logical sections. First, it uses the community VPC module to create a 2-AZ network with public and private subnets, tagged for Kubernetes and Karpenter discovery. Second, it uses the community EKS module to create the cluster itself with a small managed node group of 2× t3.medium instances, tainted so only critical addons like CoreDNS and Karpenter can run there. Third, it enables the cluster addons — CoreDNS, kube-proxy, VPC CNI, and Pod Identity Agent — which are foundational for anything else that gets installed on the cluster.m.

---

## Layer 4 — Design decisions worth calling out

Four choices worth calling out. First, single NAT gateway in non-prod — saves about ₹2,700 a month at the cost of NAT high availability, which is acceptable in dev. Second, the system node group is tainted with CriticalAddonsOnly so random workloads can't accidentally land on it and starve Karpenter of resources. Third, we enable Pod Identity Agent in addition to IRSA — Karpenter's newer default uses Pod Identity, which avoids the OIDC trust dance. Fourth, subnet tags for karpenter.sh/discovery are set here even though Karpenter isn't installed yet — that's deliberate, because Karpenter can't function without them and setting them at cluster creation time avoids drift later.

---

## Layer 5 — Zoom-ins

"In the VPC module block, private subnets get three tags: kubernetes.io/role/internal-elb=1 so internal load balancers can find them, kubernetes.io/cluster/<name>=shared so the AWS load balancer controller knows they belong to this cluster, and karpenter.sh/discovery=<name> so Karpenter can list them when picking where to launch nodes. Without any of these three tags, something downstream breaks silently.
