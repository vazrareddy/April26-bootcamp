variable "aws_region" {
  type = string
  default = "ap-south-1"
  description = "AWS region to deploy the resources"
}

variable "default_tags" {
  type = map(string)
  description = "Default tags to apply to the resources"
  default = {
    managed_by  = "terraform",
    module_name = "network",
  }
}

variable "environment" {
  type = string
  description = "Environment to deploy the resources"
  # default = "dev"
}

variable "project" {
  type = string
  description = "Project to deploy the resources"
  default = "devopsdojo"
}

variable "prefix" {
  type = string
  description = "Namespace to deploy the resources"
  default = "april26bootcamp"
}

##### 
variable "backend" {
  type = object({
    port = number
    port_name = string
    container_name = string
    image = string
    cpu = number
    memory = number
    environment = list(object({
      name = string
      value = string
    }))
  })
  description = "Backend service configuration"

  default = {
    port = 8000
    port_name = "backend"
    container_name = "backend-app"
    image = "879381241087.dkr.ecr.ap-south-1.amazonaws.com/backend:latest"
    cpu = 1024
    memory = 2048
    environment = []
  }
}


variable "domain" {
  type = string
  description = "Domain to deploy the resources"
  default = "livingdevops.org"

}

variable "subdomain" {
  type = string
  description = "Subdomain to deploy the resources"
  default = "devopsdojo"
}

variable "frontend" {
  type = object({
    port = number
    port_name = string
    container_name = string
    image = string
    cpu = number
    memory = number
    environment = list(object({
      name = string
      value = string
    }))
  })
  description = "Frontend service configuration"
  default = {
    port = 80
    port_name = "frontend"
    container_name = "frontend-app"
    image = "879381241087.dkr.ecr.ap-south-1.amazonaws.com/frontend:latest"
    cpu = 1024
    memory = 2048
    environment = []
  }
}