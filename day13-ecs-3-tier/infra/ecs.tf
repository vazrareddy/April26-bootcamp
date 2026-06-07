resource "aws_service_discovery_http_namespace" "ecs_mesh" {
  name        = "${var.environment}-${var.prefix}-${var.project}.local"
  description = "HTTP namespace for secure ECS Service Connect mesh"
}
# ecs cluster with name space

resource "aws_ecs_cluster" "main" {
  name = "${var.environment}-${var.prefix}-${var.project}"

  service_connect_defaults {
    namespace = aws_service_discovery_http_namespace.ecs_mesh.arn
  }
}

# # ecs task definition

resource "aws_ecs_task_definition" "service" {
  for_each = local.ecs_services_map
  family                   = "${var.environment}-${var.prefix}-${var.project}-${each.key}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value.cpu
  memory                   = each.value.memory

  container_definitions = jsonencode([
    {
      name      = each.value.container_name
      image     = each.value.image
      essential = true
      environment = each.value.environment
      portMappings = [
        {
          containerPort = each.value.port
          name      = each.value.port_name
          hostPort      = each.value.port
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_log_group[each.key].name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
}

# ecs service

# ecs service
resource "aws_ecs_service" "app_service" {
  for_each = local.ecs_services_map
  name            = "${var.environment}-${var.prefix}-${var.project}-${each.key}"
  cluster         = aws_ecs_cluster.main.id
  desired_count   = each.value.desired_count
  launch_type     = "FARGATE"
  task_definition = aws_ecs_task_definition.service[each.key].arn

dynamic "load_balancer" {
  for_each = each.value.need_alb ? [1] : []
  content {
    target_group_arn = aws_alb_target_group.app.arn
    container_name   = each.value.container_name
    container_port   = each.value.port
  }
}

   service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.ecs_mesh.http_name
    service {
      port_name = each.value.port_name
      client_alias {
        port     = each.value.port
        dns_name = each.value.port_name
      }
    }
  }

  network_configuration {
    subnets          = [module.network.private_subnet_ids]
    security_groups  = each.value.security_groups
    assign_public_ip = false
  }

  depends_on = [aws_alb_listener.http]
}
