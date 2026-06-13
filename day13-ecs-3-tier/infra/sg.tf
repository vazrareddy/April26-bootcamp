# security groups

# alb security group public facing inbound from internet on 80 and 443

# ecs security group for backend inbound from frontend security group
# CORS allowed

# ecs security group for frontend inbound from alb security group

# rds security group only inbound from ecs security group for backend


# security group for rds subnets

resource "aws_security_group" "rds_sg" {
  name        = "${var.environment}-${var.prefix}-${var.project}-rds-sg"
  description = "Security group for rds subnets"
  vpc_id      = module.network.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    # cidr_blocks = ["0.0.0.0/0"]
     security_groups = [aws_security_group.backend_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "april-2026-bootcamp-rds-sg"
  }
}

# ecs security group on port 8000 inbound

resource "aws_security_group" "backend_sg" {
  name        = "${var.environment}-${var.prefix}-${var.project}-backend-sg"
  description = "Security group for backend ecs service"
  vpc_id      = module.network.vpc_id

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    # cidr_blocks = ["0.0.0.0/0"]
    security_groups = [aws_security_group.frontend_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "april-2026-bootcamp-ecs-sg"
  }
}

resource "aws_security_group" "frontend_sg" {
  name        = "${var.environment}-${var.prefix}-${var.project}-frontend-sg"
  description = "Security group for frontend on port 80 from alb security group"
  vpc_id      = module.network.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    # cidr_blocks = ["0.0.0.0/0"]
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "april-2026-bootcamp-ecs-sg"
  }
}
# security group for ALB on port 80 and 443 inbound

resource "aws_security_group" "alb_sg" {
  name        = "${var.environment}-${var.prefix}-${var.project}-alb-sg"
  description = "Security group for alb "
  vpc_id      = module.network.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-${var.prefix}-${var.project}-alb-sg"
  }
}