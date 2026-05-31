variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "vpc_name" {
  description = "VPC name"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.100.0.0/16"
}

variable "subnet_cidrs" {
  description = "Subnet CIDRs"
  type        = list(string)
  default     = ["10.100.0.0/24", "10.100.1.0/24", "10.100.2.0/24"]
}

variable "enable_shared_vpc" {
  description = "Enable Shared VPC"
  type        = bool
  default     = false
}

variable "enable_cloud_nat" {
  description = "Enable Cloud NAT"
  type        = bool
  default     = true
}

variable "peer_vpc" {
  description = "Peer VPC self-link for peering"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags"
  type        = map(string)
  default     = {}
}
