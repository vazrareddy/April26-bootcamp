locals {
  
  ecs_services = [
    {
        name = "backend",
        # each.value.port
        port = 8000,
        # each.value.port_name
        port_name = "backend",
        container_name = "backend-app",
        image = "879381241087.dkr.ecr.ap-south-1.amazonaws.com/backend:latest",
        cpu = 1024,
        security_groups = [aws_security_group.backend_sg.id],
        memory = 2048,
        need_alb = false,
        environment = [
          {
            name = "FLASK_APP",
            value = "run.py"
          },
          {
            name = "FLASK_DEBUG",
            value = "1"
          },
          {
            name = "DATABASE_URL",
            value = aws_secretsmanager_secret_version.rds_password.secret_string
          },
          {
            name = "SECRET_KEY",
            value = random_password.backend_secret_key.result
          },
          {
            name = "DB_HOST",
            value = local.db_host
          },
          {
            name = "DB_PORT",
            value = "5432"
          },
          {
            name = "DB_NAME",
            value = "mydb"
          },
          {
            name = "DB_USERNAME",
            value = "postgres"
          },
          {
            name = "DB_PASSWORD",
            value = random_password.rds_password.result
          },
          {
            name = "ALLOWED_ORIGINS",
            value = "${var.subdomain}.${var.domain}"
          }
        ]
    },
    {
        name = "frontend",
        port = 80,
        port_name = "frontend",
        container_name = "frontend",
        image = "879381241087.dkr.ecr.ap-south-1.amazonaws.com/frontend:latest",
        security_groups = [aws_security_group.frontend_sg.id],
        cpu = 1024,
        memory = 2048,
        need_alb = true,
        environment = [
          {
            name = "BACKEND_URL",
            value = "http://backend:8000"
          }
        ]
    }
  ]

  # ecs_services_map = {key1 = {key = value, key = value}, key2 = {key = value, key = value}, ...}
  ecs_services_map = { for service in local.ecs_services : service.name => service }

  rds_connection_string = "postgresql://${aws_db_instance.this.username}:${random_password.rds_password.result}@${aws_db_instance.this.address}:${aws_db_instance.this.port}/${aws_db_instance.this.db_name}"
  rds_connection_string_cluster = "postgresql://${aws_rds_cluster.postgres.master_username}:${random_password.rds_password.result}@${aws_rds_cluster.postgres.endpoint}:${aws_rds_cluster.postgres.port}/${aws_rds_cluster.postgres.database_name}"
  # rds_connection_string_cluster_writer = "postgresql://${aws_rds_cluster_instance.postgres_writer.username}:${random_password.rds_password.result}@${aws_rds_cluster_instance.postgres_writer.endpoint}:5432/${aws_rds_cluster_instance.postgres_writer.db_name}"

 db_host = var.environment == "prod" ? aws_rds_cluster.postgres[0].endpoint : aws_db_instance.this[0].address
}

  output "ecs_services_map" {
  value = local.ecs_services_map
}

resource "random_password" "backend_secret_key" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

