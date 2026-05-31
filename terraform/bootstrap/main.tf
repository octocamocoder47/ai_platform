# Bootstrap infrastructure — S3 backend + DynamoDB locking
# Run this ONCE per environment, before any other Terraform

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

locals {
  bucket_name = var.bucket_name != "" ? var.bucket_name : "ai-platform-tfstate-${data.aws_caller_identity.current.account_id}"
}

data "aws_caller_identity" "current" {}

# S3 Bucket for Terraform State
resource "aws_s3_bucket" "terraform_state" {
  bucket        = local.bucket_name
  force_destroy = false

  tags = merge(var.tags, {
    Name        = local.bucket_name
    Environment = var.environment
    ManagedBy   = "terraform-bootstrap"
  })
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Deny"
      Principal = "*"
      Action = "s3:*"
      Resource = [
        aws_s3_bucket.terraform_state.arn,
        "${aws_s3_bucket.terraform_state.arn}/*"
      ]
      Condition = {
        Bool = {
          "aws:SecureTransport" = "false"
        }
      }
    }]
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# DynamoDB Table for State Locking
resource "aws_dynamodb_table" "terraform_lock" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = merge(var.tags, {
    Name        = var.dynamodb_table_name
    Environment = var.environment
    ManagedBy   = "terraform-bootstrap"
  })
}

# KMS Key for State Encryption (optional)
resource "aws_kms_key" "state" {
  count = var.create_kms_key ? 1 : 0

  description             = "KMS key for Terraform state encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      }
      Action   = "kms:*"
      Resource = "*"
    }]
  })

  tags = merge(var.tags, {
    Name        = "${local.bucket_name}-kms-key"
    Environment = var.environment
  })
}

resource "aws_kms_alias" "state" {
  count         = var.create_kms_key ? 1 : 0
  name          = "alias/${local.bucket_name}-key"
  target_key_id = aws_kms_key.state[0].key_id
}
