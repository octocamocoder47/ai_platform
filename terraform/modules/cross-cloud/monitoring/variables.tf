variable "name_prefix" {
  description = "Name prefix"
  type        = string
  default     = "ai-platform"
}

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
  default     = ""
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "gcp_workload_identity_subject" {
  description = "GCP Workload Identity subject for Mimir ingestor"
  type        = string
  default     = ""
}

variable "aws_mimir_workspace_arn" {
  description = "AWS Managed Prometheus workspace ARN"
  type        = string
  default     = ""
}

variable "aws_mimir_ingestor_role" {
  description = "Existing IAM role for Mimir ingestion (leave empty to create)"
  type        = string
  default     = ""
}

variable "gcp_mimir_writer_sa" {
  description = "Existing GCP SA for Mimir write (leave empty to create)"
  type        = string
  default     = ""
}

variable "firehose_role_arn" {
  description = "Firehose IAM role ARN for CloudWatch metrics"
  type        = string
  default     = ""
}

variable "firehose_arn" {
  description = "Firehose delivery stream ARN"
  type        = string
  default     = ""
}

variable "cloudwatch_namespace" {
  description = "CloudWatch namespace to stream"
  type        = string
  default     = "AWS/Kubernetes"
}

variable "enable_cross_cloud_dashboard" {
  description = "Enable cross-cloud Grafana workspace"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags"
  type        = map(string)
  default     = {}
}
