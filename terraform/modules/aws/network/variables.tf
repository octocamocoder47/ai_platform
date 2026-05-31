variable "name_prefix" {
  description = "Name prefix for all resources"
  type        = string
  default     = "ai-platform"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "azs" {
  description = "Availability zones"
  type        = list(string)
}

variable "public_subnets" {
  description = "Public subnet CIDRs (one per AZ)"
  type        = list(string)
}

variable "private_system_subnets" {
  description = "Private system subnet CIDRs (one per AZ)"
  type        = list(string)
}

variable "private_gpu_subnets" {
  description = "Private GPU subnet CIDRs (one per AZ)"
  type        = list(string)
  default     = []
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use single NAT Gateway for all AZs"
  type        = bool
  default     = false
}

variable "enable_transit_gateway" {
  description = "Create Transit Gateway"
  type        = bool
  default     = false
}

variable "tgw_asn" {
  description = "Transit Gateway BGP ASN"
  type        = number
  default     = 64512
}

variable "tgw_share_accounts" {
  description = "AWS account IDs to share Transit Gateway with"
  type        = list(string)
  default     = []
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs"
  type        = bool
  default     = true
}

variable "flow_logs_retention" {
  description = "Flow logs retention in days"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
