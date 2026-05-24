resource "aws_ecr_repository" "app" {
  name                 = "april-ecs-2tier"
  image_tag_mutability = "MUTABLE"

}
