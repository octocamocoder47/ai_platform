# =============================================================================
# AI Platform — Dev Environment
# =============================================================================
# This file orchestrates all Terraform modules for the dev environment.
# Variables are populated by generate-config.py from the YAML config.
# =============================================================================

terraform {
  required_version = ">= 1.9.0"

  backend "s3" {
    # Configured via backend.tf or CLI
  }
}

# Data sources
data "aws_caller_identity" "current" {}

# =============================================================================
# Network (Hub Account)
# =============================================================================
module "network" {
  source = "../../modules/aws/network"
  count  = var.account_role == "hub" || var.account_role == "all-in-one" ? 1 : 0

  name_prefix         = var.name_prefix
  environment         = var.environment
  region              = var.region
  vpc_cidr            = var.vpc_cidr
  azs                 = var.azs
  public_subnets      = var.public_subnets
  private_system_subnets  = var.private_system_subnets
  private_gpu_subnets     = var.private_gpu_subnets
  enable_nat_gateway  = var.enable_nat_gateway
  single_nat_gateway  = var.single_nat_gateway
  enable_transit_gateway = var.enable_transit_gateway
  tgw_asn             = var.tgw_asn
  tgw_share_accounts  = var.tgw_share_accounts
  enable_flow_logs    = var.enable_flow_logs
  tags                = var.tags
}

# =============================================================================
# EKS Cluster (Spoke Account)
# =============================================================================
module "eks" {
  source = "../../modules/aws/eks"
  count  = var.account_role == "spoke" || var.account_role == "all-in-one" ? 1 : 0

  name_prefix    = var.name_prefix
  environment    = var.environment
  cluster_version = var.cluster_version
  vpc_id         = var.account_role == "all-in-one" ? module.network[0].vpc_id : data.terraform_remote_state.network[0].outputs.vpc_id
  vpc_cidr       = var.account_role == "all-in-one" ? var.vpc_cidr : data.terraform_remote_state.network[0].outputs.vpc_cidr
  subnet_ids     = var.account_role == "all-in-one" ? module.network[0].private_system_subnet_ids : data.terraform_remote_state.network[0].outputs.private_system_subnet_ids
  system_instance_types = var.system_instance_types
  system_min_size       = var.system_min_size
  system_max_size       = var.system_max_size
  gpu_node_groups       = var.gpu_node_groups
  karpenter_enabled     = var.karpenter_enabled
  endpoint_private_access = var.endpoint_private_access
  endpoint_public_access  = var.endpoint_public_access
  tags              = var.tags
}

# =============================================================================
# IRSA Roles
# =============================================================================
module "irsa" {
  source = "../../modules/aws/irsa"
  count  = var.account_role == "spoke" || var.account_role == "all-in-one" ? 1 : 0

  cluster_name     = module.eks[0].cluster_name
  oidc_provider_arn = module.eks[0].oidc_provider_arn
  oidc_provider_url = module.eks[0].oidc_provider_url
  service_accounts = var.irsa_roles
  tags             = var.tags
}

# =============================================================================
# GCP (Multi-Cloud — when enabled)
# =============================================================================
module "gcp_network" {
  source = "../../modules/gcp/network"
  count  = var.gcp_enabled ? 1 : 0

  project_id  = var.gcp_project_id
  region      = var.gcp_region
  vpc_name    = "${var.name_prefix}-${var.environment}-vpc"
  vpc_cidr    = var.gcp_vpc_cidr
  enable_cloud_nat = true
  tags        = var.tags
}

module "gke" {
  source = "../../modules/gcp/gke"
  count  = var.gcp_enabled ? 1 : 0

  project_id     = var.gcp_project_id
  region         = var.gcp_region
  cluster_name   = "${var.name_prefix}-${var.environment}-gke"
  vpc_self_link  = module.gcp_network[0].vpc_self_link
  subnet_self_link = module.gcp_network[0].subnet_self_links[0]
  node_pools     = var.gcp_node_pools
  tags           = var.tags
}

# =============================================================================
# Cross-Cloud VPN (Multi-Cloud)
# =============================================================================
module "cross_cloud_vpn" {
  source = "../../modules/cross-cloud/vpn"
  count  = var.gcp_enabled ? 1 : 0

  aws_region    = var.region
  aws_vpc_id    = module.network[0].vpc_id
  aws_tgw_id    = module.network[0].transit_gateway_id
  gcp_project   = var.gcp_project_id
  gcp_region    = var.gcp_region
  gcp_network   = module.gcp_network[0].vpc_self_link
  gcp_router_name = "${var.name_prefix}-${var.environment}-router"
  bgp_asn       = var.cross_cloud_bgp_asn
  tags          = var.tags
}
