# =============================================================================
# Dev Environment Variables
# All values are populated by generate-config.py from platform-config.yaml
# =============================================================================

variable "name_prefix" {
  description = "Name prefix for all resources"
  type        = string
  default     = "ai-platform"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "account_role" {
  description = "Account role (hub, spoke, shared, security, all-in-one)"
  type        = string
  default     = "all-in-one"
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default = {
    Environment = "dev"
    ManagedBy   = "terraform"
    Project     = "ai-platform"
    CostCenter  = "platform-engineering"
  }
}

# --- Network ---
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "public_subnets" {
  description = "Public subnet CIDRs"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_system_subnets" {
  description = "Private system subnet CIDRs"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
}

variable "private_gpu_subnets" {
  description = "Private GPU subnet CIDRs"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24", "10.0.22.0/24"]
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Single NAT Gateway"
  type        = bool
  default     = false
}

variable "enable_transit_gateway" {
  description = "Enable Transit Gateway"
  type        = bool
  default     = false
}

variable "tgw_asn" {
  description = "Transit Gateway ASN"
  type        = number
  default     = 64512
}

variable "tgw_share_accounts" {
  description = "Accounts to share TGW with"
  type        = list(string)
  default     = []
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs"
  type        = bool
  default     = true
}

# --- EKS ---
variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"
}

variable "system_instance_types" {
  description = "System node instance types"
  type        = list(string)
  default     = ["t3.medium", "t3.large"]
}

variable "system_min_size" {
  description = "System node min size"
  type        = number
  default     = 1
}

variable "system_max_size" {
  description = "System node max size"
  type        = number
  default     = 3
}

variable "gpu_node_groups" {
  description = "GPU node group configs"
  type = map(object({
    instance_types = list(string)
    disk_size      = optional(number, 100)
    min_size       = number
    max_size       = number
    spot           = optional(bool, false)
    accelerator    = string
    labels         = optional(map(string), {})
  }))
  default = {}
}

variable "karpenter_enabled" {
  description = "Enable Karpenter"
  type        = bool
  default     = false
}

variable "endpoint_private_access" {
  description = "Private API endpoint"
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Public API endpoint"
  type        = bool
  default     = false
}

# --- IRSA ---
variable "irsa_roles" {
  description = "IRSA role configurations"
  type = map(object({
    policy      = optional(string, null)
    policy_arns = optional(list(string), null)
  }))
  default = {}
}

# --- GCP ---
variable "gcp_enabled" {
  description = "Enable GCP multi-cloud"
  type        = bool
  default     = false
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

variable "gcp_vpc_cidr" {
  description = "GCP VPC CIDR"
  type        = string
  default     = "10.100.0.0/16"
}

variable "gcp_node_pools" {
  description = "GKE node pool configs"
  type = map(object({
    machine_type = string
    min_size     = number
    max_size     = number
    gpu_type     = optional(string, null)
    gpu_count    = optional(number, 0)
    spot         = optional(bool, false)
  }))
  default = {}
}

# --- Cross-Cloud ---
variable "cross_cloud_bgp_asn" {
  description = "Cross-cloud BGP ASN"
  type        = number
  default     = 64512
}
