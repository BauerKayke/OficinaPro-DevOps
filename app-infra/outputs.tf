# Outputs para a infraestrutura com 2 nodes K3s

# --- MASTER OUTPUTS ---

output "k3s_master_public_ip" {
  description = "IP Público do K3s Master"
  value       = aws_eip.k3s_master_eip.public_ip
}

output "k3s_master_private_ip" {
  description = "IP Privado do K3s Master"
  value       = aws_instance.k3s_master.private_ip
}

output "k3s_master_id" {
  description = "ID da instância EC2 Master"
  value       = aws_instance.k3s_master.id
}

# --- WORKER OUTPUTS ---
# Worker removido para economia de custos

# --- ALB OUTPUTS ---

output "alb_dns_name" {
  description = "DNS do Application Load Balancer"
  value       = aws_lb.app_alb.dns_name
}

output "alb_listener_arn" {
  description = "ARN do Listener HTTP do ALB (necessário para VPC Link)"
  value       = aws_lb_listener.http.arn
}

# --- CLUSTER OUTPUTS ---

output "cluster_api_endpoint" {
  description = "Endpoint da API do K3s Cluster (Master)"
  value       = "https://${aws_eip.k3s_master_eip.public_ip}:6443"
}

output "security_group_id" {
  description = "ID do Security Group do K3s Cluster"
  value       = aws_security_group.k3s_cluster_sg.id
}

# --- SSH COMMANDS ---

output "ssh_master_command" {
  description = "Comando SSH para conectar ao Master"
  value       = "ssh -i ~/.ssh/chave_nova.pem ubuntu@${aws_eip.k3s_master_eip.public_ip}"
}

# --- SSM COMMANDS ---

output "ssm_master_command" {
  description = "Comando para conectar ao Master via Systems Manager"
  value       = "aws ssm start-session --target ${aws_instance.k3s_master.id} --region ${var.aws_region}"
}

# --- CLUSTER STATUS COMMANDS ---

output "check_nodes_command" {
  description = "Comando para verificar status dos nodes no cluster"
  value       = "kubectl get nodes -o wide"
}

output "check_pods_command" {
  description = "Comando para verificar pods em todos os nodes"
  value       = "kubectl get pods -n oficinapro-prod -o wide"
}

# --- CUSTO ESTIMADO ---

output "monthly_cost_estimate" {
  description = "Custo mensal estimado da infraestrutura (Spot Instance)"
  value       = "1x m7i-flex.large Spot = ~$26-30/mês (economia 85-90% vs On-Demand)"
}
