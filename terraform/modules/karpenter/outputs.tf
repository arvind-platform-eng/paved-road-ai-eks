output "node_role_arn" {
  description = "IAM role ARN attached to Karpenter-provisioned nodes"
  value       = aws_iam_role.karpenter_node.arn
}

output "controller_role_arn" {
  description = "IAM role ARN used by the Karpenter controller"
  value       = aws_iam_role.karpenter_controller.arn
}

output "interruption_queue_name" {
  description = "SQS queue name for spot interruption events"
  value       = aws_sqs_queue.karpenter_interruption.name
}
