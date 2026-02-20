output "consolidated_db_endpoint" {
  description = "Consolidated RDS endpoint for all databases"
  value       = aws_db_instance.consolidated.endpoint
}

output "consolidated_db_address" {
  description = "Consolidated RDS address (without port)"
  value       = aws_db_instance.consolidated.address
}

output "databases" {
  description = "List of databases in the consolidated instance"
  value = [
    "os_db",
    "billing_db",
    "execution_db",
    "customer_db",
    "saga_db"
  ]
}

output "dynamodb_billing_idempotency_table" {
  description = "DynamoDB table for billing idempotency"
  value       = aws_dynamodb_table.billing_idempotency.name
}

output "dynamodb_payment_status_table" {
  description = "DynamoDB table for payment status"
  value       = aws_dynamodb_table.payment_status.name
}

output "rds_security_group_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds.id
}

output "cost_savings" {
  description = "Estimated monthly cost savings"
  value       = "~$58/month vs 5 separate RDS instances"
}
