output "container_repository_urls" {
  description = "Container repository URLs"
  value = {
    for k, v in aws_ecr_repository.containers : k => v.repository_url
  }
}

output "model_repository_urls" {
  description = "Model repository URLs"
  value = {
    for k, v in aws_ecr_repository.models : k => v.repository_url
  }
}

output "container_repository_arns" {
  description = "Container repository ARNs"
  value = {
    for k, v in aws_ecr_repository.containers : k => v.arn
  }
}
