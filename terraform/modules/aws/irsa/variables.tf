variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL"
  type        = string
}

variable "service_accounts" {
  description = "Map of service account keys to IAM policies"
  type = map(object({
    policy      = optional(string, null)
    policy_arns = optional(list(string), null)
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
