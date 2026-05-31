locals {
  
  ecs_services = [
    {
        name = "backend",
        port = 8000,
        container_name = "backend",
        image = "879381241087.dkr.ecr.ap-south-1.amazonaws.com/backend:latest",
        cpu = 1024,
        memory = 2048,
        need_alb = false,
        environment = [
          {
            name = "DB_LINK",
            value = "postgresql://${aws_db_instance.db.username}:${aws_db_instance.db.password}@${aws_db_instance.db.endpoint}/${aws_db_instance.db.name}"
          }
        ]
    },
    {
        name = "frontend",
        port = 8000,
        container_name = "frontend",
        image = "879381241087.dkr.ecr.ap-south-1.amazonaws.com/frontend:latest",
        cpu = 1024,
        memory = 2048,
        need_alb = true,
        environment = [
          {
            name = "DB_LINK",
            value = "postgresql://${aws_db_instance.db.username}:${aws_db_instance.db.password}@${aws_db_instance.db.endpoint}/${aws_db_instance.db.name}"
          }
        ]
    }
  ]
}

