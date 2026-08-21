resource "aws_ecs_cluster" "this" {
  name = "${var.service}-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = var.tags
}
