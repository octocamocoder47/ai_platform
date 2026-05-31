variable "name_prefix" {
  description = "Name prefix"
  type        = string
  default     = "ai-platform"
}

variable "aws_private_zone_id" {
  description = "AWS Route53 private zone ID"
  type        = string
}

variable "aws_vpc_id" {
  description = "AWS VPC ID"
  type        = string
}

variable "aws_dns_domain" {
  description = "AWS private DNS domain (e.g. ai-platform.dev.internal)"
  type        = string
}

variable "gcp_private_zone_name" {
  description = "GCP Cloud DNS zone name"
  type        = string
}

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_dns_domain" {
  description = "GCP private DNS domain"
  type        = string
}

variable "gcp_network_url" {
  description = "GCP VPC network self-link"
  type        = string
}

variable "gcp_dns_ips" {
  description = "GCP DNS resolver IPs"
  type        = list(string)
}

variable "resolver_subnet_ids" {
  description = "Subnet IDs for Route53 resolver endpoints"
  type        = list(string)
}

variable "resolver_sg_id" {
  description = "Security group ID for Route53 resolver endpoints"
  type        = string
}

variable "resolver_ips" {
  description = "IPs for Route53 resolver endpoints"
  type        = list(string)
}

variable "aws_resolver_ips" {
  description = "Route53 outbound resolver IPs"
  type        = list(string)
}

variable "tags" {
  description = "Tags"
  type        = map(string)
  default     = {}
}
