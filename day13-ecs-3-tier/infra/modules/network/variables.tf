# vpc  cidr
variable "vpc_cidr" {
  type        = string
  description = "cidr for vpc "
}

# vpc_name
variable "vpc_name" {
  type        = string
  description = "name for vpc "
}

variable "private_subnet_data" {
  type = list(object({
    cidr              = string
    availability_zone = string
    prefix            = string
  }))
  description = "Map of subnets to create, categorized by type (public/private)"
}

variable "public_subnet_data" {
  type = list(object({
    cidr              = string
    availability_zone = string
    prefix            = string
  }))
  description = "Map of subnets to create, categorized by type (public/private)"
}

variable "need_nat_gateway" {
  type        = bool
  description = "if nat gateway is needed"
  default     = false
}

variable "need_single_nat_gateway" {
  type        = bool
  description = "if you need only 1 nat gatway"
  default     = false
}

variable "enable_dns_hostnames" {
  type = bool
  description = "Enable DNS hostnames in the VPC"
  default = false
}

variable "enable_dns_support" {
  type = bool
  default = true
}

variable "aws_region" {
  type = string
#   default = "ap-south-1"
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