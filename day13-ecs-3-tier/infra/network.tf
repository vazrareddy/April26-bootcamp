module "network" {
  source = "./modules/network"
  # vpc variables
  vpc_cidr = "10.0.0.0/16"
  vpc_name = "${var.environment}-${var.project}"
  private_subnet_data = [
    {
      cidr              = "10.0.1.0/24"
      availability_zone = "ap-south-1a"
      prefix            = "private"
    },
    {
      cidr              = "10.0.2.0/24"
      availability_zone = "ap-south-1b"
      prefix            = "private"
    },
    {
      cidr              = "10.0.3.0/24"
      availability_zone = "ap-south-1c"
      prefix            = "private"
    }
  ]
  public_subnet_data = [
    {
      cidr              = "10.0.2.0/24"
      availability_zone = "ap-south-1b"
      prefix            = "public"
    },
    {
      cidr              = "10.0.3.0/24"
      availability_zone = "ap-south-1c"
      prefix            = "public"
    },
    {
      cidr              = "10.0.4.0/24"
      availability_zone = "ap-south-1d"
      prefix            = "public"
    }
  ]
  aws_region = var.aws_region
  default_tags = {
    managed_by  = "terraform",
    module_name = "network",
    environment = var.environment,
    project = var.project,
  }
  need_nat_gateway = true
  need_single_nat_gateway = false
}