variable "bucket_name" {
  description = "S3 bucket name for Terraform state. Auto-generated if empty."
  type        = string
  default     = ""
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name for state locking"
  type        = string
  default     = "ai-platform-tfstate-lock"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "create_kms_key" {
  description = "Create KMS key for state encryption"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy   = "terraform-bootstrap"
    Environment = "dev"
  }
}
