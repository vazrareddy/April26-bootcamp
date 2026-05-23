provider "aws" {

  region = "ap-south-1"
  default_tags {
    tags = {
      Environment = "Test"
      Terraform   = true
      repo        = "April26-bootcamp"
    }
  }
}

# provider "aws" {
#     alias = "provider-us-east-1"

#   region = "us-east-1"
# }

# locals {
#   providers = ["aws", "provider-us-east-1"]
# }


# resource "aws_vpc" "this" {
#     for_each = 
#   cidr_block = "10.0.0.0/16"
#   provider = provider-us-east-1
#   enable_dns_hostnames = true
#   enable_dns_support = true
#   region = var.aws_region
#   tags = {
#     Name = "april-2026-bootcamp-vpc"
#   }
# }