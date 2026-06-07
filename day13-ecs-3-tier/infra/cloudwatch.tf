resource "aws_cloudwatch_log_group" "ecs_log_group" {
  for_each = local.ecs_services_map
  name              = "/ecs/${var.environment}-${var.prefix}-${var.project}-${each.key}"
  retention_in_days = 7

  tags = {
    Name = "/ecs/${var.environment}-${var.prefix}-${var.project}-${each.key}"
  }
}

