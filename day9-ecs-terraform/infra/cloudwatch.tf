resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/${var.ecs_task_def}"
  retention_in_days = 7

  tags = {
    Name = "/ecs/${var.ecs_task_def}"
  }
}

