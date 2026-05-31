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
  default = "dev"
}

variable "project" {
  type = string
  description = "Project to deploy the resources"
  default = "april26-bootcamp"
}