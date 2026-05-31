variable "name_prefix" {
  description = "Name prefix"
  type        = string
  default     = "ai-platform"
}

variable "environment" {
  description = "Environment"
  type        = string
}

variable "force_destroy" {
  description = "Force destroy S3 buckets"
  type        = bool
  default     = false
}

variable "enable_versioning" {
  description = "Enable S3 versioning"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Backup retention in days"
  type        = number
  default     = 30
}

variable "enable_efs" {
  description = "Enable EFS filesystem"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID (required for EFS)"
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "VPC CIDR (required for EFS)"
  type        = string
  default     = ""
}

variable "private_subnet_ids" {
  description = "Private subnet IDs (required for EFS)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags"
  type        = map(string)
  default     = {}
}
