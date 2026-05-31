terraform {
  required_version = ">= 1.9.0"
}

locals {
  name_prefix = var.name_prefix != "" ? var.name_prefix : "ai-platform"
}

# S3 Bucket for Model Storage
resource "aws_s3_bucket" "model_storage" {
  bucket        = "${local.name_prefix}-${var.environment}-model-storage"
  force_destroy = var.force_destroy

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${var.environment}-model-storage"
  })
}

resource "aws_s3_bucket_versioning" "model_storage" {
  bucket = aws_s3_bucket.model_storage.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "model_storage" {
  bucket = aws_s3_bucket.model_storage.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "model_storage" {
  bucket = aws_s3_bucket.model_storage.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket for Backups
resource "aws_s3_bucket" "backup_storage" {
  bucket        = "${local.name_prefix}-${var.environment}-backups"
  force_destroy = false

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${var.environment}-backups"
  })
}

resource "aws_s3_bucket_versioning" "backup_storage" {
  bucket = aws_s3_bucket.backup_storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backup_storage" {
  bucket = aws_s3_bucket.backup_storage.id
  rule {
    id     = "expire-old-backups"
    status = "Enabled"
    expiration {
      days = var.backup_retention_days
    }
  }
}

# EFS Filesystem (shared model storage)
resource "aws_efs_file_system" "shared" {
  count = var.enable_efs ? 1 : 0

  creation_token = "${local.name_prefix}-${var.environment}-shared"
  encrypted      = true
  performance_mode = "generalPurpose"
  throughput_mode  = "elastic"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${var.environment}-shared"
  })
}

resource "aws_efs_mount_target" "shared" {
  count = var.enable_efs ? length(var.private_subnet_ids) : 0

  file_system_id  = aws_efs_file_system.shared[0].id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs[0].id]
}

resource "aws_security_group" "efs" {
  count = var.enable_efs ? 1 : 0

  name        = "${local.name_prefix}-${var.environment}-efs-sg"
  description = "Security group for EFS"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = var.tags
}
