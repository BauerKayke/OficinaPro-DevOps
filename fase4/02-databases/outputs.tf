output "os_db_endpoint" {
  description = "OS Database endpoint"
  value       = aws_db_instance.os_db.endpoint
}

output "billing_db_endpoint" {
  description = "Billing Database endpoint"
  value       = aws_db_instance.billing_db.endpoint
}

output "execution_db_endpoint" {
  description = "Execution Database endpoint"
  value       = aws_db_instance.execution_db.endpoint
}

output "customer_db_endpoint" {
  description = "Customer Database endpoint"
  value       = aws_db_instance.customer_db.endpoint
}

output "saga_db_endpoint" {
  description = "Saga Database endpoint"
  value       = aws_db_instance.saga_db.endpoint
}

output "rds_security_group_id" {
  description = "RDS Security Group ID"
  value       = aws_security_group.rds.id
}

output "dynamodb_billing_idempotency_table" {
  description = "DynamoDB Billing Idempotency table name"
  value       = aws_dynamodb_table.billing_idempotency.name
}

output "dynamodb_payment_status_table" {
  description = "DynamoDB Payment Status table name"
  value       = aws_dynamodb_table.payment_status.name
}
