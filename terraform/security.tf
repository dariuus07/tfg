resource "aws_security_group" "attacker" {
  name        = "${var.project_name}-attacker-sg"
  description = "Adversary emulation node. Administrative SSH ingress and unrestricted egress."
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "Administrative SSH from operator network."
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

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

resource "aws_security_group" "victim" {
  name        = "${var.project_name}-victim-sg"
  description = "Monitored target node. Web ingress restricted to the adversary node and operator."
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "Administrative SSH from operator network."
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description     = "HTTP application traffic from the adversary node."
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.attacker.id]
  }

  ingress {
    description     = "HTTPS application traffic from the adversary node."
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.attacker.id]
  }

  ingress {
    description = "HTTP verification access from operator network."
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

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

resource "aws_security_group" "manager" {
  name        = "${var.project_name}-manager-sg"
  description = "Wazuh SIEM manager. Dashboard restricted to operator and telemetry to monitored nodes."
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "Administrative SSH from operator network."
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "Wazuh dashboard access from operator network."
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description     = "Wazuh agent event telemetry from the monitored target."
    from_port       = 1514
    to_port         = 1514
    protocol        = "tcp"
    security_groups = [aws_security_group.victim.id]
  }

  ingress {
    description     = "Wazuh agent enrollment from the monitored target."
    from_port       = 1515
    to_port         = 1515
    protocol        = "tcp"
    security_groups = [aws_security_group.victim.id]
  }

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
