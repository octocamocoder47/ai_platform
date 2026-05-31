output "model_storage_bucket" {
  description = "Model storage S3 bucket name"
  value       = aws_s3_bucket.model_storage.id
}

output "model_storage_bucket_arn" {
  description = "Model storage S3 bucket ARN"
  value       = aws_s3_bucket.model_storage.arn
}

output "backup_storage_bucket" {
  description = "Backup S3 bucket name"
  value       = aws_s3_bucket.backup_storage.id
}

output "efs_file_system_id" {
  description = "EFS filesystem ID"
  value       = var.enable_efs ? aws_efs_file_system.shared[0].id : null
}

output "efs_dns_name" {
  description = "EFS DNS name"
  value       = var.enable_efs ? aws_efs_file_system.shared[0].dns_name : null
}
