variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "name_prefix" {
  description = "Name prefix"
  type        = string
  default     = "ai-platform"
}

variable "dns_name" {
  description = "DNS zone name (e.g. ai-platform.dev.internal)"
  type        = string
}

variable "network_url" {
  description = "Self link of the VPC network"
  type        = string
}

variable "ingress_records" {
  description = "Map of name -> IP for ingress records"
  type        = map(string)
  default     = {}
}

variable "service_records" {
  description = "Map of name -> IP for service records"
  type        = map(string)
  default     = {}
}

variable "peer_with_aws" {
  description = "Peer with AWS DNS"
  type        = bool
  default     = false
}

variable "aws_dns_name" {
  description = "AWS private DNS zone name for peering"
  type        = string
  default     = ""
}

variable "peer_network_url" {
  description = "Network URL to peer with"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags"
  type        = map(string)
  default     = {}
}
