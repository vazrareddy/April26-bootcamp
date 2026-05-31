# security groups

# alb security group public facing inbound from internet on 80 and 443

# ecs security group for backend inbound from frontend security group
# CORS allowed

# ecs security group for frontend inbound from alb security group

# rds security group only inbound from ecs security group for backend