terraform {
  # major vesrion
  required_version = ">=1.1"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # minor version
      version = "~> 6.0"
    }

    random = {
      source = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}