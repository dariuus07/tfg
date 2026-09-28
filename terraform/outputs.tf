# IP publica del manager: acceso SSH (usuario ec2-user) y dashboard en :443.
output "manager_public_ip" {
  description = "Public IPv4 address of the Wazuh SIEM manager node."
  value       = aws_instance.manager.public_ip
}

# IP publica de la victima: verificacion de Juice Shop en el puerto 80.
output "victim_public_ip" {
  description = "Public IPv4 address of the monitored target node."
  value       = aws_instance.victim.public_ip
}

# IP publica del atacante: acceso SSH para inspeccionar los logs de ataque.
output "attacker_public_ip" {
  description = "Public IPv4 address of the adversary emulation node."
  value       = aws_instance.attacker.public_ip
}

# IP privada del manager: es la que se inyecta en la victima como WAZUH_MANAGER.
output "manager_private_ip" {
  description = "Private IPv4 address of the manager, injected into the victim agent."
  value       = aws_instance.manager.private_ip
}

# IP privada de la victima: es la que se inyecta en el atacante como TARGET_IP.
output "victim_private_ip" {
  description = "Private IPv4 address of the victim, injected into the attacker as target."
  value       = aws_instance.victim.private_ip
}
