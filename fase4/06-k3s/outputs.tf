output "master_ip" {
  description = "K3s server public IP"
  value       = aws_eip.k3s_server.public_ip
}

output "server_instance_id" {
  description = "K3s server instance ID"
  value       = aws_instance.k3s_server.id
}

output "agent_instance_id" {
  description = "K3s agent instance ID"
  value       = aws_instance.k3s_agent.id
}
