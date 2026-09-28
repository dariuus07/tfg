# Security Group del nodo ATACANTE.
# Solo admite SSH desde el operador y permite salida total (herramientas y
# paquetes). No recibe trafico de ningun otro nodo.
resource "aws_security_group" "attacker" {
  name        = "${var.project_name}-attacker-sg"
  description = "Adversary emulation node. Administrative SSH ingress and unrestricted egress."
  vpc_id      = aws_vpc.lab.id

  # Entrada: SSH (22) unicamente desde la red del operador.
  ingress {
    description = "Administrative SSH from operator network."
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # Salida: sin restricciones (descarga de paquetes y ejecucion de ataques).
  egress {
    description = "Unrestricted outbound access for attack tooling and package retrieval."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-attacker-sg"
  }
}

# Security Group del nodo VICTIMA.
# Expone la web solo al atacante y al operador; nunca a Internet.
resource "aws_security_group" "victim" {
  name        = "${var.project_name}-victim-sg"
  description = "Monitored target node. Web ingress restricted to the adversary node and operator."
  vpc_id      = aws_vpc.lab.id

  # Entrada: SSH (22) solo desde el operador.
  ingress {
    description = "Administrative SSH from operator network."
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # Entrada: HTTP (80) solo desde el Security Group del atacante.
  ingress {
    description     = "HTTP application traffic from the adversary node."
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.attacker.id]
  }

  # Entrada: HTTPS (443) solo desde el Security Group del atacante.
  ingress {
    description     = "HTTPS application traffic from the adversary node."
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.attacker.id]
  }

  # Entrada: HTTP (80) tambien desde el operador para verificacion manual.
  ingress {
    description = "HTTP verification access from operator network."
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # Salida: sin restricciones (pull de imagen Docker y telemetria al manager).
  egress {
    description = "Unrestricted outbound for container image pulls and telemetry to the manager."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-victim-sg"
  }
}

# Security Group del nodo MANAGER (Wazuh SIEM + Ollama).
# Dashboard solo para el operador; telemetria solo desde la victima.
resource "aws_security_group" "manager" {
  name        = "${var.project_name}-manager-sg"
  description = "Wazuh SIEM manager. Dashboard restricted to operator and telemetry to monitored nodes."
  vpc_id      = aws_vpc.lab.id

  # Entrada: SSH (22) solo desde el operador.
  ingress {
    description = "Administrative SSH from operator network."
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # Entrada: dashboard de Wazuh (443) solo desde el operador.
  ingress {
    description = "Wazuh dashboard access from operator network."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  # Entrada: eventos del agente (1514) solo desde el Security Group de la victima.
  ingress {
    description     = "Wazuh agent event telemetry from the monitored target."
    from_port       = 1514
    to_port         = 1514
    protocol        = "tcp"
    security_groups = [aws_security_group.victim.id]
  }

  # Entrada: alta/registro del agente (1515) solo desde la victima.
  ingress {
    description     = "Wazuh agent enrollment from the monitored target."
    from_port       = 1515
    to_port         = 1515
    protocol        = "tcp"
    security_groups = [aws_security_group.victim.id]
  }

  # Salida: sin restricciones (descarga de Wazuh, Ollama y el modelo TinyLlama).
  egress {
    description = "Unrestricted outbound for package retrieval and model download."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-manager-sg"
  }
}
