terraform {
  required_version = ">= 1.9.0"
}

locals {
  name_prefix = var.name_prefix != "" ? var.name_prefix : "ai-platform"
}

# ECR Repository for container images
resource "aws_ecr_repository" "containers" {
  for_each = toset(var.container_repositories)

  name                 = "${local.name_prefix}/${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}/${each.key}"
  })
}

# ECR Repository for model artifacts (OCI)
resource "aws_ecr_repository" "models" {
  for_each = toset(var.model_repositories)

  name                 = "${local.name_prefix}/models/${each.key}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}/models/${each.key}"
  })
}

# Lifecycle policy for container repos
resource "aws_ecr_lifecycle_policy" "containers" {
  for_each = aws_ecr_repository.containers

  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 30 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 30
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# Repository policy — deny HTTP
resource "aws_ecr_repository_policy" "main" {
  for_each = merge(aws_ecr_repository.containers, aws_ecr_repository.models)

  repository = each.value.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyHTTP"
      Effect = "Deny"
      Principal = "*"
      Action = "*"
      Condition = {
        Bool = {
          "aws:SecureTransport" = "false"
        }
      }
      Resource = each.value.arn
    }]
  })
}
