# AMI estandar de Amazon Linux 2023 (nodos manager y atacante).
# Se resuelve dinamicamente desde un parametro publico de AWS Systems Manager,
# de modo que siempre se usa la imagen mas reciente y parcheada.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# AMI ECS-optimized de Amazon Linux 2023 (nodo victima).
# Esta imagen oficial de AWS trae Docker YA instalado, por lo que Juice Shop
# puede lanzarse sin instalar el motor de contenedores en el arranque.
data "aws_ssm_parameter" "al2023_docker" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

# Nodo MANAGER: Wazuh SIEM + Ollama (motor de inferencia local).
# Es el primer nodo del grafo; el resto depende de su IP privada.
resource "aws_instance" "manager" {
  ami                    = nonsensitive(data.aws_ssm_parameter.al2023.value)
  instance_type          = var.manager_instance_type
  subnet_id              = aws_subnet.public.id
  key_name               = var.ssh_key_name
  vpc_security_group_ids  = [aws_security_group.manager.id]
  # Script de aprovisionamiento inyectado en el primer arranque (cloud-init).
  user_data = file("${path.module}/scripts/manager_bootstrap.sh")

  root_block_device {
    volume_type = "gp3"
    volume_size = var.manager_root_volume_size
    encrypted   = true
  }

  tags = {
    Name = "${var.project_name}-wazuh-siem-manager"
    Role = "manager"
  }
}

# Nodo VICTIMA: OWASP Juice Shop en Docker + agente de Wazuh.
# Usa la AMI con Docker preinstalado.
resource "aws_instance" "victim" {
  ami                    = nonsensitive(data.aws_ssm_parameter.al2023_docker.value)
  instance_type          = var.victim_instance_type
  subnet_id              = aws_subnet.public.id
  key_name               = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.victim.id]

  # AUTOMATIZACION: se antepone al script una linea que exporta la IP privada
  # REAL del manager (resuelta por Terraform). Esta referencia crea ademas la
  # dependencia implicita victima -> manager en el grafo, sin necesidad de
  # depends_on. El contenido del script se inserta como texto y no se vuelve a
  # interpretar, por lo que las variables bash del script quedan intactas.
  user_data = <<-EOT
    #!/usr/bin/env bash
    export WAZUH_MANAGER_IP="${aws_instance.manager.private_ip}"
    ${file("${path.module}/scripts/victim_bootstrap.sh")}
  EOT

  root_block_device {
    volume_type = "gp3"
    volume_size = var.node_root_volume_size
    encrypted   = true
  }

  tags = {
    Name = "${var.project_name}-victim-juice-shop"
    Role = "victim"
  }
}

# Nodo ATACANTE: ejecuta la suite de ataque contra la victima.
resource "aws_instance" "attacker" {
  ami                    = nonsensitive(data.aws_ssm_parameter.al2023.value)
  instance_type          = var.attacker_instance_type
  subnet_id              = aws_subnet.public.id
  key_name               = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.attacker.id]

  # AUTOMATIZACION: se inyectan dos valores. TARGET_IP es la IP privada real de
  # la victima (crea la dependencia atacante -> victima). ATTACK_SIMULATOR_B64
  # es el simulador de ataques Python codificado en base64, de modo que el nodo
  # queda autocontenido y no depende de clonar ningun repositorio externo.
  user_data = <<-EOT
    #!/usr/bin/env bash
    export TARGET_IP="${aws_instance.victim.private_ip}"
    export ATTACK_SIMULATOR_B64="${base64encode(file("${path.module}/scripts/attack_simulator.py"))}"
    ${file("${path.module}/scripts/attacker_bootstrap.sh")}
  EOT

  root_block_device {
    volume_type = "gp3"
    volume_size = var.node_root_volume_size
    encrypted   = true
  }

  tags = {
    Name = "${var.project_name}-adversary-traffic-generator"
    Role = "attacker"
  }
}
