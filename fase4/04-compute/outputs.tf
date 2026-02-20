output "k3s_instance_id" {
  description = "K3s EC2 instance ID"
  value       = aws_instance.k3s.id
}

output "k3s_master_public_ip" {
  description = "K3s public IP"
  value       = aws_eip.k3s.public_ip
}

output "k3s_private_ip" {
  description = "K3s private IP"
  value       = aws_instance.k3s.private_ip
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.main.arn
}

output "k3s_security_group_id" {
  description = "K3s security group ID"
  value       = aws_security_group.k3s.id
}

output "alb_security_group_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}
