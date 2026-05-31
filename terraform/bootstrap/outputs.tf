output "state_bucket" {
  description = "S3 bucket name for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "dynamodb_table" {
  description = "DynamoDB table for state locking"
  value       = aws_dynamodb_table.terraform_lock.id
}

output "kms_key_arn" {
  description = "KMS key ARN for state encryption"
  value       = var.create_kms_key ? aws_kms_key.state[0].arn : null
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.terraform_state.arn
}
