# string variables


variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "ecs_cluster_name" {
  type    = string
  default = "april-2tier-ecs-cluster"
}

variable "ecs_task_def" {
  default = "april-2tier-taskdef"

}
variable "ecs_service" {
  default = "april-2tier-ecs-service"
}

variable "app_image" {
  default = "879381241087.dkr.ecr.ap-south-1.amazonaws.com/april-ecs-2tier:latest"
}

variable "port" {
  type    = number
  default = 8000
}

variable "domain" {
  default = "livingdevops.org" 
}

variable "alb_apsouth1_zoneid" {
  default = "Z11ORPS3UI2S3F"
  
}

variable "container_name" {
  default = "2tier"
}