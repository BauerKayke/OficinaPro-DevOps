output "os_events_queue_url" {
  description = "OS Events queue URL"
  value       = aws_sqs_queue.os_events.url
}

output "os_commands_queue_url" {
  description = "OS Commands queue URL"
  value       = aws_sqs_queue.os_commands.url
}

output "billing_events_queue_url" {
  description = "Billing Events queue URL"
  value       = aws_sqs_queue.billing_events.url
}

output "billing_commands_queue_url" {
  description = "Billing Commands queue URL"
  value       = aws_sqs_queue.billing_commands.url
}

output "execution_events_queue_url" {
  description = "Execution Events queue URL"
  value       = aws_sqs_queue.execution_events.url
}

output "execution_commands_queue_url" {
  description = "Execution Commands queue URL"
  value       = aws_sqs_queue.execution_commands.url
}

output "saga_dlq_url" {
  description = "Saga Dead Letter Queue URL"
  value       = aws_sqs_queue.saga_dlq.url
}

output "sqs_access_policy_arn" {
  description = "IAM Policy ARN for SQS access"
  value       = aws_iam_policy.sqs_access.arn
}

output "cost_savings" {
  description = "Estimated monthly cost savings"
  value       = "~$0.40/month (Standard queues have Free Tier, FIFO doesn't)"
}
