# Bloque de configuracion de Terraform: fija la version del binario y los
# proveedores necesarios para garantizar despliegues reproducibles.
terraform {
  # Exige Terraform 1.5.0 o superior (sintaxis usada en este proyecto).
  required_version = ">= 1.5.0"

  required_providers {
    # Proveedor oficial de AWS anclado a la serie 5.x para evitar que una
    # version mayor futura introduzca cambios incompatibles.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Configuracion del proveedor de AWS: define la region y las etiquetas
# comunes que se aplicaran automaticamente a todos los recursos.
provider "aws" {
  region = var.aws_region

  # default_tags propaga estas etiquetas a cada recurso creado, lo que
  # facilita la identificacion, el filtrado y el borrado por proyecto.
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "lab"
      ManagedBy   = "terraform"
    }
  }
}
