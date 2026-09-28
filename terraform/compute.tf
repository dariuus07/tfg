data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_instance" "manager" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.manager_instance_type
  subnet_id              = aws_subnet.public.id
  key_name               = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.manager.id]
  user_data              = file("${path.module}/scripts/manager_bootstrap.sh")

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

resource "aws_instance" "victim" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.victim_instance_type
  subnet_id              = aws_subnet.public.id
  key_name               = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.victim.id]
  user_data              = file("${path.module}/scripts/victim_bootstrap.sh")

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

resource "aws_instance" "attacker" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.attacker_instance_type
  subnet_id              = aws_subnet.public.id
  key_name               = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.attacker.id]
  user_data              = file("${path.module}/scripts/attacker_bootstrap.sh")

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
