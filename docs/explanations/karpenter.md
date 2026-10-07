# Karpenter module — a walkthrough

*File: `terraform/modules/karpenter/main.tf`*

This is my working explanation of the Karpenter module. Written in the order I'd say it in an interview or code review — outside layers first, details only on request.

---

## Layer 1 — Purpose

This module installs Karpenter on the EKS cluster and configures a GPU spot NodePool ready to provision inference nodes on demand.

---

## Layer 2 — Inputs and outputs

The module takes the cluster name, a Karpenter Helm chart version, and a tag map as inputs. It outputs the node IAM role ARN, the controller IAM role ARN, and the SQS interruption queue name — everything a downstream operator or debugging session needs to trace an issue back to its IAM identity.

---

## Layer 3 — The story in five chunks

The file has five logical sections.

First, it creates the IAM role Karpenter's controller uses to manage EC2 instances, attached via EKS Pod Identity rather than the older IRSA pattern. Second, it creates the IAM role every EC2 instance Karpenter launches will assume, with the four standard EKS worker policies attached — worker, CNI, ECR read, and SSM. Third, it sets up an SQS queue and EventBridge rules so that AWS's two-minute spot interruption warnings flow to Karpenter, which then drains the affected node gracefully. Fourth, it installs the Karpenter Helm chart into the `kube-system` namespace with the right service account name so Pod Identity binds correctly and the controller lands on the tainted system node group. Fifth, it creates the `EC2NodeClass` and `NodePool` custom resources that define what GPU instances Karpenter is actually allowed to provision — g5 and g4dn families, spot-first with on-demand fallback, tainted so only pods that tolerate `nvidia.com/gpu` can schedule on them.

---

## Layer 4 — Design decisions worth calling out

Five choices are worth mentioning in a design conversation.

**Pod Identity over IRSA for the controller role.** IRSA works, but requires setting up an OIDC provider trust relationship and annotating the service account. Pod Identity is AWS's newer pattern that skips the trust dance — a single `aws_eks_pod_identity_association` resource binds the role to the service account. Less code, fewer failure modes, one addon (`eks-pod-identity-agent`) as the dependency.

**Custom SQS queue for spot interruption, not the AWS-managed default.** Karpenter needs to react within the 2-minute spot warning window. Owning the queue means we control retention, encryption, and the EventBridge rule that populates it. Trade-off: two extra AWS resources to maintain vs. faster reaction and clearer failure logs.

**`consolidationPolicy: WhenEmpty` rather than `WhenUnderutilized`.** This is the critical GPU choice. `WhenUnderutilized` would let Karpenter continuously repack workloads onto fewer nodes to save cost — but for GPU inference, disrupting a running vLLM pod means losing 90 seconds of model reload time. `WhenEmpty` only disrupts nodes when they're truly empty, at some cost efficiency loss.

**Instance family list of `["g5", "g4dn"]`, not just `["g5"]`.** Spot availability of `g5.xlarge` varies by AZ and time of day. Including `g4dn` gives Karpenter a fallback with similar performance and cost characteristics. Without the fallback, a spot capacity crunch in one family means no nodes provision at all.

**Hard limits at 100 CPU and 400 GiB memory on the NodePool.** This is a safety net against a runaway workload spinning up unlimited GPU nodes and blowing the AWS bill. If we hit the limit, new pods stay pending — which is loud and fixable — instead of silently draining the budget.

---

## Layer 5 — Zoom-ins (only when asked)

### If asked: "Walk me through the spot interruption flow"

AWS's EC2 service publishes a spot interruption warning event when it needs to reclaim a spot instance. The EventBridge rule in this module matches those events by their source and detail-type. The matched event is forwarded to the SQS queue. Karpenter's controller polls this queue continuously — it's how it discovers the interruption. When Karpenter sees a message, it looks up which of its managed nodes the interrupted instance backs, cordons that node so no new pods land on it, and drains existing pods gracefully — which for vLLM means calling the pre-stop hook that gives the pod 30 seconds to finish in-flight requests before eviction. All of this needs to complete inside the 2-minute warning window.

### If asked: "Why those specific IAM permissions?"

The controller role's policy has two statements. The first is the broad EC2 statement — `RunInstances`, `TerminateInstances`, `CreateFleet`, `CreateLaunchTemplate` — because Karpenter's core job is launching and terminating EC2 instances. The `DescribeInstanceTypes`, `DescribeSpotPriceHistory`, and `pricing:GetProducts` permissions are what let Karpenter pick the cheapest instance type for a given workload. The `ssm:GetParameter` permission is for AMI discovery — Karpenter reads the AL2023 latest AMI ID from SSM Parameter Store rather than hard-coding it. The `iam:PassRole` is what lets Karpenter attach the node role to the instances it creates. The second statement is scoped tightly to just the SQS queue this module creates, giving the least privilege needed to consume interruption events. Nothing else is granted.

### If asked: "Why `expireAfter: 168h`?"

That's 7 days. It forces Karpenter to rotate every node once a week. The security benefit is automatic patch pickup — new nodes come up with the latest AL2023 AMI, so we never accumulate long-lived nodes with stale kernel packages. The operational benefit is that every node is proven "still replaceable" every week, which surfaces problems like broken node bootstrapping before they become emergencies during a real spot interruption.
