locals {

  ecs_services = [
    {
      name = "backend",
      # each.value.port
      port = 8000,
      # each.value.port_name
      port_name       = "backend",
      container_name  = "backend-app",
      image           = "879381241087.dkr.ecr.ap-south-1.amazonaws.com/${var.environment}-${var.project}-backend:latest",
      cpu             = 512,
      security_groups = [aws_security_group.backend_sg.id],
      memory          = 1024,
      need_alb        = false, desired_count = 1,
      environment = [
        {
          name  = "FLASK_DEBUG",
          value = "1"
        },
        {
          name  = "DATABASE_URL",
          value = aws_secretsmanager_secret_version.rds_password.secret_string
        },
        {
          name  = "SECRET_KEY",
          value = random_password.backend_secret_key.result
        },
        {
          name  = "DB_HOST",
          value = local.db_host
        },
        {
          name  = "DB_PORT",
          value = "5432"
        },
        {
          name  = "DB_NAME",
          value = "mydb"
        },
        {
          name  = "DB_USERNAME",
          value = "postgres"
        },
        {
          name  = "DB_PASSWORD",
          value = random_password.rds_password.result
        },
        {
          name  = "ALLOWED_ORIGINS",
          value = "${var.subdomain}.${var.domain}"
        },
        {
          name  = "CLOUDWATCH_METRIC_NAMESPACE",
          value = "${var.environment}/${var.project}/Backend"
        }
      ]
    },
    {
      name           = "frontend",
      port           = 80,
      port_name      = "frontend",
      container_name = "frontend",
      # no implict dependency on ecr repository
      image           = "879381241087.dkr.ecr.ap-south-1.amazonaws.com/${var.environment}-${var.project}-frontend:latest",
      security_groups = [aws_security_group.frontend_sg.id],
      cpu             = 512,
      memory          = 1024,
      need_alb        = true,
      desired_count   = 1,
      environment = [
        {
          name  = "BACKEND_URL",
          value = "http://backend:8000"
        }
      ]
    }
  ]

  # ecs_services_map = {key1 = {key = value, key = value}, key2 = {key = value, key = value}, ...}
  ecs_services_map = { for service in local.ecs_services : service.name => service }

  db_host = var.environment == "prod" ? aws_rds_cluster.postgres[0].endpoint : aws_db_instance.postgres[0].address
}

output "ecs_services_map" {
  value     = local.ecs_services_map
  sensitive = true
}

resource "random_password" "backend_secret_key" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

