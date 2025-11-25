# Saídas de dados da infraestrutura da aplicação

output "instance_public_ip" {
  description = "O IP público da instância EC2 que roda o K3s."
  value       = aws_eip.k3s_eip.public_ip
}

output "instance_id" {
  description = "O ID da instância EC2."
  value       = aws_instance.k3s_node.id
}
