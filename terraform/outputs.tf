output "manager_public_ip" {
  description = "Public IPv4 address of the Wazuh SIEM manager node."
  value       = aws_instance.manager.public_ip
}

output "victim_public_ip" {
  description = "Public IPv4 address of the monitored target node."
  value       = aws_instance.victim.public_ip
}

output "attacker_public_ip" {
  description = "Public IPv4 address of the adversary emulation node."
  value       = aws_instance.attacker.public_ip
}
