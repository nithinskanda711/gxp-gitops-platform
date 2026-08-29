# ---------------------------------------------------------------------------
# ECR only. Deliberately separated from the EKS stack so that `apply` here can
# never create a control plane or a NAT gateway by accident.
#
# Cost at the scale this project operates: storage is billed per GB-month and
# the lifecycle policy below caps the repository at a fixed number of images,
# so the bill stays in small change. There is no hourly charge for a registry.
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "node_monitor" {
  name = "${var.project}/node-monitor"

  # The evidence story depends on a tag meaning exactly one image forever.
  # A mutable tag makes "we deployed 0.1.0" an unverifiable claim.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "node_monitor" {
  repository = aws_ecr_repository.node_monitor.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the ${var.retain_image_count} most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.retain_image_count
      }
      action = { type = "expire" }
    }]
  })
}

data "aws_caller_identity" "current" {}
