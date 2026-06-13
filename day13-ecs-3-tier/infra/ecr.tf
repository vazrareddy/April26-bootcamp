# ecr repository

resource "aws_ecr_repository" "ecr_repositories" {
    for_each = local.ecs_services_map
    name = "${var.environment}-${var.project}-${each.key}"
    image_tag_mutability = "MUTABLE"
}

output "ecr_repository_url_backend" {
    value = aws_ecr_repository.ecr_repositories["backend"].repository_url
}
output "ecr_repository_url_frontend" {
    value = aws_ecr_repository.ecr_repositories["frontend"].repository_url
}