variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
}

variable "vpc_name" {
  description = "VPC name"
  type        = string
}

variable "subnet_name" {
  description = "Subnet name"
  type        = string
}

variable "pod_cidr" {
  description = "Pod IP CIDR range"
  type        = string
  default     = "10.200.0.0/16"
}

variable "service_cidr" {
  description = "Service IP CIDR range"
  type        = string
  default     = "172.20.0.0/16"
}

variable "system_machine_type" {
  description = "System node machine type"
  type        = string
  default     = "e2-standard-4"
}

variable "system_min_size" {
  description = "System node pool min size"
  type        = number
  default     = 1
}

variable "system_max_size" {
  description = "System node pool max size"
  type        = number
  default     = 5
}

variable "enable_gpu" {
  description = "Enable GPU node pool"
  type        = bool
  default     = false
}

variable "gpu_machine_type" {
  description = "GPU node machine type"
  type        = string
  default     = "g2-standard-4"
}

variable "gpu_type" {
  description = "GPU accelerator type"
  type        = string
  default     = "nvidia-l4"
}

variable "gpu_count" {
  description = "Number of GPUs per node"
  type        = number
  default     = 1
}

variable "gpu_min_size" {
  description = "GPU node pool min size"
  type        = number
  default     = 0
}

variable "gpu_max_size" {
  description = "GPU node pool max size"
  type        = number
  default     = 5
}

variable "enable_binary_auth" {
  description = "Enable Binary Authorization"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags"
  type        = map(string)
  default     = {}
}
