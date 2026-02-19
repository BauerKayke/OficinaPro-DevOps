output "nat_instance_id" {
  description = "NAT instance ID"
  value       = aws_instance.nat.id
}

output "nat_instance_public_ip" {
  description = "NAT instance public IP"
  value       = aws_eip.nat.public_ip
}

output "nat_instance_private_ip" {
  description = "NAT instance private IP"
  value       = aws_instance.nat.private_ip
}

output "cost_savings" {
  description = "Estimated monthly cost savings"
  value       = "~$29/month vs NAT Gateway ($32.85 vs $3.80)"
}
