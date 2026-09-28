variable "aws_region" {
  description = "AWS region where the laboratory infrastructure is deployed."
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Prefix applied to resource names and tags for identification."
  type        = string
  default     = "tfg-devsecops-lab"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "The project_name must contain only lowercase letters, digits and hyphens."
  }
}

variable "availability_zone" {
  description = "Availability Zone used for the public subnet placement."
  type        = string
  default     = "eu-west-1a"
}

variable "vpc_cidr" {
  description = "Primary CIDR block allocated to the laboratory VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "The vpc_cidr value must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet hosting the three laboratory nodes."
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "The public_subnet_cidr value must be a valid IPv4 CIDR block."
  }
}

variable "ssh_key_name" {
  description = "Name of an existing EC2 SSH key pair used for administrative access."
  type        = string
}

variable "admin_cidr" {
  description = "Operator source CIDR authorised for administrative SSH and dashboard access."
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && var.admin_cidr != "0.0.0.0/0"
    error_message = "The admin_cidr must be a valid IPv4 CIDR and must not be 0.0.0.0/0."
  }
}
