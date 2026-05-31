variable "name_prefix" {
  description = "Name prefix"
  type        = string
  default     = "ai-platform"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_vpc_id" {
  description = "AWS VPC ID"
  type        = string
}

variable "aws_cidr" {
  description = "AWS VPC CIDR"
  type        = string
}

variable "aws_tgw_id" {
  description = "AWS Transit Gateway ID"
  type        = string
}

variable "aws_tgw_route_table_id" {
  description = "AWS Transit Gateway route table ID"
  type        = string
  default     = ""
}

variable "gcp_project" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
}

variable "gcp_network" {
  description = "GCP VPC self link"
  type        = string
}

variable "gcp_cidr" {
  description = "GCP VPC CIDR"
  type        = string
}

variable "gcp_bgp_asn" {
  description = "GCP BGP ASN"
  type        = number
  default     = 64513
}

variable "gcp_vpn_gateway_ip" {
  description = "GCP VPN gateway public IP"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags"
  type        = map(string)
  default     = {}
}
