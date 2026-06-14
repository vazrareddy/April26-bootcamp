locals {
  # Custom metric namespace emitted by the Flask backend via Embedded Metric Format (EMF).
  # EMF log lines in /ecs/...-backend are auto-converted to CloudWatch metrics here.
  backend_metric_namespace = "${var.environment}/${var.project}/Backend"
  alarm_actions            = [var.alarm_sns_topic_arn]
}

resource "aws_cloudwatch_log_group" "ecs_log_group" {
  for_each          = local.ecs_services_map
  name              = "/ecs/${var.environment}-${var.prefix}-${var.project}-${each.key}"
  retention_in_days = 7

  tags = {
    Name = "/ecs/${var.environment}-${var.prefix}-${var.project}-${each.key}"
  }
}

# ---------------------------------------------------------------------------
# Log-based metric filters
# ---------------------------------------------------------------------------

# Counts backend HTTP 5xx responses parsed from structured request logs.
resource "aws_cloudwatch_log_metric_filter" "backend_5xx" {
  name           = "${var.environment}-${var.project}-backend-5xx"
  log_group_name = aws_cloudwatch_log_group.ecs_log_group["backend"].name
  pattern        = "{ $.status >= 500 }"

  metric_transformation {
    name          = "Backend5xxCount"
    namespace     = local.backend_metric_namespace
    value         = "1"
    default_value = "0"
  }
}

# Counts ERROR-level log lines (health check failures, unhandled errors, etc.).
resource "aws_cloudwatch_log_metric_filter" "backend_errors" {
  name           = "${var.environment}-${var.project}-backend-errors"
  log_group_name = aws_cloudwatch_log_group.ecs_log_group["backend"].name
  pattern        = "{ $.levelname = \"ERROR\" }"

  metric_transformation {
    name          = "BackendErrorCount"
    namespace     = local.backend_metric_namespace
    value         = "1"
    default_value = "0"
  }
}

# Counts frontend proxy failures visible to clients (Express http-proxy-middleware).
resource "aws_cloudwatch_log_metric_filter" "frontend_proxy_errors" {
  name           = "${var.environment}-${var.project}-frontend-proxy-errors"
  log_group_name = aws_cloudwatch_log_group.ecs_log_group["frontend"].name
  pattern        = "Proxy error"

  metric_transformation {
    name          = "FrontendProxyErrorCount"
    namespace     = local.backend_metric_namespace
    value         = "1"
    default_value = "0"
  }
}

# ---------------------------------------------------------------------------
# ALB alarms — frontend availability and user-facing errors
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_targets" {
  alarm_name          = "${var.environment}-${var.project}-alb-unhealthy-targets"
  alarm_description   = "Frontend ECS tasks are failing ALB health checks on /health"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions

  dimensions = {
    LoadBalancer = aws_alb.app.arn_suffix
    TargetGroup  = aws_alb_target_group.app.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_target_5xx" {
  alarm_name          = "${var.environment}-${var.project}-alb-target-5xx"
  alarm_description   = "HTTP 5xx responses from the frontend target group"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions

  dimensions = {
    LoadBalancer = aws_alb.app.arn_suffix
    TargetGroup  = aws_alb_target_group.app.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_high_latency" {
  alarm_name          = "${var.environment}-${var.project}-alb-high-latency"
  alarm_description   = "ALB target response time is above 3 seconds on average"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 3
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions

  dimensions = {
    LoadBalancer = aws_alb.app.arn_suffix
    TargetGroup  = aws_alb_target_group.app.arn_suffix
  }
}

# ---------------------------------------------------------------------------
# ECS alarms — container resource pressure
# ---------------------------------------------------------------------------
# ECS/Fargate publishes CPU and memory at ~60s granularity; period must match.

resource "aws_cloudwatch_metric_alarm" "backend_cpu_high" {
  alarm_name          = "${var.environment}-${var.project}-backend-cpu-high"
  alarm_description   = "Backend ECS service CPU utilization is above 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app_service["backend"].name
  }
}

resource "aws_cloudwatch_metric_alarm" "backend_memory_high" {
  alarm_name          = "${var.environment}-${var.project}-backend-memory-high"
  alarm_description   = "Backend ECS service memory utilization is above 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app_service["backend"].name
  }
}

# ---------------------------------------------------------------------------
# Application alarms — custom metrics from Flask EMF instrumentation
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "backend_request_latency" {
  alarm_name          = "${var.environment}-${var.project}-backend-request-latency"
  alarm_description   = "Backend average request duration exceeds 2000 ms (EMF aggregate metric)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "RequestDurationOverall"
  namespace           = local.backend_metric_namespace
  period              = 60
  statistic           = "Average"
  threshold           = 2000
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions

  dimensions = {
    Service = "backend"
  }
}

resource "aws_cloudwatch_metric_alarm" "backend_5xx_rate" {
  alarm_name          = "${var.environment}-${var.project}-backend-5xx-rate"
  alarm_description   = "Backend is returning 5xx responses (from log metric filter)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Backend5xxCount"
  namespace           = local.backend_metric_namespace
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "backend_error_rate" {
  alarm_name          = "${var.environment}-${var.project}-backend-error-rate"
  alarm_description   = "Backend ERROR log lines detected"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BackendErrorCount"
  namespace           = local.backend_metric_namespace
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "frontend_proxy_error_rate" {
  alarm_name          = "${var.environment}-${var.project}-frontend-proxy-errors"
  alarm_description   = "Frontend proxy errors reaching the backend (timeouts/upstream failures)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FrontendProxyErrorCount"
  namespace           = local.backend_metric_namespace
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "backend_health_check_failure" {
  alarm_name          = "${var.environment}-${var.project}-backend-health-failure"
  alarm_description   = "Backend health check failed — likely RDS connectivity issue"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthCheckFailure"
  namespace           = local.backend_metric_namespace
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions

  dimensions = {
    Check = "database"
  }
}
