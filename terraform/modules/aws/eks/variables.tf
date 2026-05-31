variable "name_prefix" {
  description = "Name prefix for all resources"
  type        = string
  default     = "ai-platform"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for EKS cluster"
  type        = list(string)
}

variable "endpoint_private_access" {
  description = "Enable private API server endpoint"
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Enable public API server endpoint"
  type        = bool
  default     = false
}

variable "cluster_log_types" {
  description = "EKS cluster log types"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "vpc_cni_version" {
  description = "VPC CNI add-on version"
  type        = string
  default     = "v1.18.0-eksbuild.1"
}

variable "kube_proxy_version" {
  description = "kube-proxy add-on version"
  type        = string
  default     = "v1.31.0-eksbuild.1"
}

variable "coredns_version" {
  description = "CoreDNS add-on version"
  type        = string
  default     = "v1.11.1-eksbuild.4"
}

variable "ebs_csi_version" {
  description = "EBS CSI driver add-on version"
  type        = string
  default     = "v1.35.0-eksbuild.1"
}

variable "node_role_arn" {
  description = "IAM role ARN for node groups"
  type        = string
  default     = ""
}

variable "karpenter_enabled" {
  description = "Enable Karpenter"
  type        = bool
  default     = false
}

variable "karpenter_node_role_arn" {
  description = "IAM role ARN for Karpenter nodes"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
