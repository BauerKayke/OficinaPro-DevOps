output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.main.arn
}

output "capacity_provider_name" {
  description = "EC2 capacity provider name"
  value       = aws_ecs_capacity_provider.ec2.name
}

output "security_group_id" {
  description = "Security group ID for ECS instances"
  value       = aws_security_group.ecs_instances.id
}

output "task_execution_role_arn" {
  description = "Task execution role ARN for ECS tasks (CloudWatch logs)"
  value       = aws_iam_role.ecs_task_execution.arn
}
