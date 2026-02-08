output "master_public_ip" {
  description = "IP Público do Master Node"
  value       = aws_eip.master_eip.public_ip
}

output "master_private_ip" {
  description = "IP Privado do Master Node"
  value       = aws_instance.k3s_master.private_ip
}

output "worker_public_ip" {
  description = "IP Público do Worker Node"
  value       = aws_eip.worker_eip.public_ip
}

output "worker_private_ip" {
  description = "IP Privado do Worker Node"
  value       = aws_instance.k3s_worker.private_ip
}

output "alb_dns_name" {
  description = "DNS do Load Balancer Interno"
  value       = aws_lb.app_alb.dns_name
}

output "alb_listener_arn" {
  description = "ARN do Listener do ALB (para uso no API Gateway VPC Link)"
  value       = aws_lb_listener.http.arn
}

output "cluster_api_endpoint" {
  description = "Endpoint da API do Kubernetes"
  value       = "https://${aws_eip.master_eip.public_ip}:6443"
}

output "ssh_command_master" {
  description = "Comando para acessar o Master"
  value       = "ssh -i ${var.key_name}.pem ubuntu@${aws_eip.master_eip.public_ip}"
}

output "ssh_command_worker" {
  description = "Comando para acessar o Worker"
  value       = "ssh -i ${var.key_name}.pem ubuntu@${aws_eip.worker_eip.public_ip}"
}
