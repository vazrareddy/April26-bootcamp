# Want ALB for frontend service only
# alb 
resource "aws_alb" "app" {
  name            = "${var.environment}-${var.project}-alb"
  internal        = false
  security_groups = [aws_security_group.alb_sg.id]
  subnets         = module.network.public_subnet_ids

  tags = {
    Name = "${var.environment}-${var.prefix}-${var.project}-alb"
  }

}

# alb target group
resource "aws_alb_target_group" "app" {
  name     = "${var.environment}-${var.project}-tg"
#   port     = var.frontend.port
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.network.vpc_id
  target_type = "ip"

  health_check {
    path     = "/health"
    protocol = "HTTP"
    matcher  = "200"
    interval = 30
    timeout  = 5
  }

  tags = {
    Name = "${var.environment}-${var.prefix}-${var.project}-alb-target-group"
  }

}

# alb lister for port 80
resource "aws_alb_listener" "http" {
  load_balancer_arn = aws_alb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.app.arn
  }
}


# alb lister for port 443
resource "aws_alb_listener" "https" {
    load_balancer_arn = aws_alb.app.arn
    port              = 443
    protocol          = "HTTPS"
    ssl_policy        = "ELBSecurityPolicy-2016-08"
    certificate_arn   = aws_acm_certificate_validation.app_cert.certificate_arn
    
    default_action {
        type             = "forward"
        target_group_arn = aws_alb_target_group.app.arn
  
}
}