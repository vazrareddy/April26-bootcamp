locals {
  # Custom metric namespace emitted by the Flask backend via Embedded Metric Format (EMF).
  # EMF log lines in /ecs/...-backend are auto-converted to CloudWatch metrics here.
  backend_metric_namespace = "${var.environment}/${var.project}/Backend"
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
# These turn structured JSON log lines from the Flask app into countable metrics.
# The backend logs {"status": 500, ...} on each request via python-json-logger.

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

# ---------------------------------------------------------------------------
# ALB alarms — frontend availability and user-facing errors
# ---------------------------------------------------------------------------

# Fires when the ALB target group has any unhealthy frontend tasks.
# Usually means the frontend container failed its /health check or is not reachable.
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

  dimensions = {
    LoadBalancer = aws_alb.app.arn_suffix
    TargetGroup  = aws_alb_target_group.app.arn_suffix
  }
}

# Fires when the frontend (via ALB) returns too many 5xx responses to clients.
# Captures proxy errors and upstream backend failures visible to users.
resource "aws_cloudwatch_metric_alarm" "alb_target_5xx" {
  alarm_name          = "${var.environment}-${var.project}-alb-target-5xx"
  alarm_description   = "High rate of HTTP 5xx responses from the frontend target group"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_alb.app.arn_suffix
    TargetGroup  = aws_alb_target_group.app.arn_suffix
  }
}

# Fires when average response time through the ALB exceeds 3 seconds.
# Useful for catching slow page loads or backend latency regressions.
resource "aws_cloudwatch_metric_alarm" "alb_high_latency" {
  alarm_name          = "${var.environment}-${var.project}-alb-high-latency"
  alarm_description   = "ALB target response time is above 3 seconds on average"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 3
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_alb.app.arn_suffix
    TargetGroup  = aws_alb_target_group.app.arn_suffix
  }
}

# ---------------------------------------------------------------------------
# ECS alarms — container resource pressure
# ---------------------------------------------------------------------------

# Fires when the backend ECS service average CPU exceeds 80%.
# Indicates the Flask/gunicorn workers may need more CPU or horizontal scaling.
resource "aws_cloudwatch_metric_alarm" "backend_cpu_high" {
  alarm_name          = "${var.environment}-${var.project}-backend-cpu-high"
  alarm_description   = "Backend ECS service CPU utilization is above 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app_service["backend"].name
  }
}

# Fires when the backend ECS service average memory exceeds 80%.
# Helps catch memory leaks or undersized task memory limits.
resource "aws_cloudwatch_metric_alarm" "backend_memory_high" {
  alarm_name          = "${var.environment}-${var.project}-backend-memory-high"
  alarm_description   = "Backend ECS service memory utilization is above 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app_service["backend"].name
  }
}

# ---------------------------------------------------------------------------
# Application alarms — custom metrics from Flask EMF instrumentation
# ---------------------------------------------------------------------------

# Fires when average backend request duration (EMF metric) exceeds 2 seconds.
# EMF lines are emitted on every API request and auto-indexed by CloudWatch.
resource "aws_cloudwatch_metric_alarm" "backend_request_latency" {
  alarm_name          = "${var.environment}-${var.project}-backend-request-latency"
  alarm_description   = "Backend average request duration exceeds 2000 ms (from EMF metrics)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "RequestDuration"
  namespace           = local.backend_metric_namespace
  period              = 60
  statistic           = "Average"
  threshold           = 2000
  treat_missing_data  = "notBreaching"
}

# Fires when the backend emits 5 or more 5xx responses in a 5-minute window.
# Derived from structured JSON logs via the Backend5xxCount metric filter above.
resource "aws_cloudwatch_metric_alarm" "backend_5xx_rate" {
  alarm_name          = "${var.environment}-${var.project}-backend-5xx-rate"
  alarm_description   = "Backend is returning 5xx responses (from log metric filter)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Backend5xxCount"
  namespace           = local.backend_metric_namespace
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  treat_missing_data  = "notBreaching"
}

# Fires when the /health endpoint reports database connectivity failures.
# EMF HealthCheckFailure metric is emitted when SELECT 1 against RDS fails.
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
}
