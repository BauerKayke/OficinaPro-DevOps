output "k3s_host_public_ip" {
  description = "IP Público da instância EC2 rodando K3s"
  value       = aws_eip.k3s_eip.public_ip
}

output "k3s_host_id" {
  description = "ID da instância EC2"
  value       = aws_instance.k3s_node.id
}

output "alb_dns_name" {
  description = "DNS do Application Load Balancer"
  value       = aws_lb.app_alb.dns_name
}
