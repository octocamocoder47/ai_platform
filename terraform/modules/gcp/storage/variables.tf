variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for storage"
  type        = string
  default     = "us-central1"
}

variable "kms_key_name" {
  description = "KMS key name for encryption"
  type        = string
  default     = ""
}

variable "storage_admin_sa" {
  description = "Storage admin service account email"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags"
  type        = map(string)
  default     = {}
}
