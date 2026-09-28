# Region de AWS donde se despliega todo el laboratorio.
variable "aws_region" {
  description = "AWS region where the laboratory infrastructure is deployed."
  type        = string
  default     = "eu-west-1"
}

# Prefijo aplicado a los nombres y etiquetas de los recursos.
variable "project_name" {
  description = "Prefix applied to resource names and tags for identification."
  type        = string
  default     = "tfg-devsecops-lab"

  # Solo se permiten minusculas, digitos y guiones (compatibilidad con
  # nombres de recursos de AWS).
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "The project_name must contain only lowercase letters, digits and hyphens."
  }
}

# Zona de disponibilidad concreta donde se ubica la subred publica.
variable "availability_zone" {
  description = "Availability Zone used for the public subnet placement."
  type        = string
  default     = "eu-west-1a"
}

# Rango de direcciones (CIDR) asignado a la VPC del laboratorio.
variable "vpc_cidr" {
  description = "Primary CIDR block allocated to the laboratory VPC."
  type        = string
  default     = "10.0.0.0/16"

  # Comprueba que el valor es un CIDR IPv4 valido antes de llamar a la API.
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "The vpc_cidr value must be a valid IPv4 CIDR block."
  }
}

# Rango de la subred publica que aloja los tres nodos.
variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet hosting the three laboratory nodes."
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "The public_subnet_cidr value must be a valid IPv4 CIDR block."
  }
}

# Nombre de un par de claves SSH ya existente en la region (acceso admin).
variable "ssh_key_name" {
  description = "Name of an existing EC2 SSH key pair used for administrative access."
  type        = string
}

# CIDR del operador autorizado para SSH y para el dashboard de Wazuh.
variable "admin_cidr" {
  description = "Operator source CIDR authorised for administrative SSH and dashboard access."
  type        = string

  # Aplica el principio de minimo privilegio: exige un CIDR valido y prohibe
  # explicitamente abrir el acceso administrativo a todo Internet (0.0.0.0/0).
  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && var.admin_cidr != "0.0.0.0/0"
    error_message = "The admin_cidr must be a valid IPv4 CIDR and must not be 0.0.0.0/0."
  }
}

# Tipo de instancia del manager (Wazuh Indexer/Dashboard + Ollama exigen RAM).
variable "manager_instance_type" {
  description = "EC2 instance type for the Wazuh SIEM manager and local inference engine."
  type        = string
  default     = "t3.xlarge"
}

# Tipo de instancia del nodo victima (contenedor Juice Shop).
variable "victim_instance_type" {
  description = "EC2 instance type for the monitored target workload."
  type        = string
  default     = "t3.medium"
}

# Tipo de instancia del nodo atacante (scripts de ataque ligeros).
variable "attacker_instance_type" {
  description = "EC2 instance type for the adversary emulation node."
  type        = string
  default     = "t3.small"
}

# Tamano del disco raiz del manager (Wazuh + modelo de IA ocupan espacio).
variable "manager_root_volume_size" {
  description = "Root EBS volume size in GiB for the manager node."
  type        = number
  default     = 50
}

# Tamano del disco raiz de los nodos victima y atacante.
variable "node_root_volume_size" {
  description = "Root EBS volume size in GiB for the victim and attacker nodes."
  type        = number
  default     = 20
}

# Token del bot de Telegram (generado por @BotFather). Marcado como sensible
# para que Terraform no lo muestre en la salida ni en los logs de plan/apply.
variable "telegram_token" {
  description = "Telegram Bot API token used to dispatch alert notifications."
  type        = string
  sensitive   = true
}

# Identificador del chat/canal de Telegram destinatario de las alertas.
variable "telegram_chat_id" {
  description = "Telegram chat identifier that receives the alert notifications."
  type        = string
}

# Modelo local servido por Ollama para generar las mitigaciones.
variable "ollama_model" {
  description = "Ollama model pulled and queried locally for remediation guidance."
  type        = string
  default     = "tinyllama"
}
