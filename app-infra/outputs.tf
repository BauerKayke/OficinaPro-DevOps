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

output "alb_listener_arn" {
  description = "ARN do Listener HTTP do ALB (necessário para VPC Link)"
  value       = aws_lb_listener.http.arn
}

output "ssm_connect_command" {
  description = "Comando para conectar via Systems Manager (fallback SSH)"
  value       = "aws ssm start-session --target ${aws_instance.k3s_node.id} --region ${var.aws_region}"
}

output "ssh_test_command" {
  description = "Comando para testar conectividade SSH"
  value       = "timeout 10 bash -c 'cat < /dev/null > /dev/tcp/${aws_eip.k3s_eip.public_ip}/22' && echo '✅ SSH OK' || echo '❌ SSH FALHOU'"
}

output "security_group_id" {
  description = "ID do Security Group do K3s"
  value       = aws_security_group.k3s_sg.id
}
