variable "name_prefix" {
  description = "Name prefix"
  type        = string
  default     = "ai-platform"
}

variable "environment" {
  description = "Environment"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for private zone association"
  type        = string
}

variable "zone_name" {
  description = "Private DNS zone name"
  type        = string
  default     = ""
}

variable "create_public_zone" {
  description = "Create public hosted zone"
  type        = bool
  default     = false
}

variable "public_zone_name" {
  description = "Public DNS zone name"
  type        = string
  default     = ""
}

variable "internal_lb_ip" {
  description = "Internal load balancer IP for A records"
  type        = string
  default     = "10.0.1.10"
}

variable "enable_vault" {
  description = "Create Vault DNS record"
  type        = bool
  default     = false
}

variable "delegate_to_accounts" {
  description = "Map of subdomain -> NS records for cross-account delegation"
  type        = map(map(list(string)))
  default     = {}
}

variable "tags" {
  description = "Tags"
  type        = map(string)
  default     = {}
}
