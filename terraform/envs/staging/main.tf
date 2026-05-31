# Staging environment — production-like but smaller
# Uses the same modules as dev but with different variables

module "network" {
  source = "../../modules/aws/network"

  name_prefix         = "ai-platform"
  environment         = "staging"
  region              = "us-west-2"
  vpc_cidr            = "10.10.0.0/16"
  azs                 = ["us-west-2a", "us-west-2b", "us-west-2c"]
  public_subnets      = ["10.10.1.0/24", "10.10.2.0/24", "10.10.3.0/24"]
  private_system_subnets  = ["10.10.10.0/24", "10.10.11.0/24", "10.10.12.0/24"]
  private_gpu_subnets     = ["10.10.20.0/24", "10.10.21.0/24", "10.10.22.0/24"]
  enable_nat_gateway  = true
  single_nat_gateway  = false
  enable_transit_gateway = true
  enable_flow_logs    = true
  tags = {
    Environment = "staging"
    ManagedBy   = "terraform"
    Project     = "ai-platform"
  }
}

module "eks" {
  source = "../../modules/aws/eks"

  name_prefix    = "ai-platform"
  environment    = "staging"
  cluster_version = "1.31"
  vpc_id         = module.network.vpc_id
  vpc_cidr       = module.network.vpc_cidr
  subnet_ids     = module.network.private_system_subnet_ids

  system_instance_types = ["t3.large"]
  system_min_size       = 2
  system_max_size       = 5

  gpu_node_groups = {
    gpu-inference = {
      instance_types = ["g5.xlarge"]
      min_size       = 1
      max_size       = 5
      accelerator    = "nvidia-tesla-t4"
    }
  }

  karpenter_enabled = true
  tags = {
    Environment = "staging"
    ManagedBy   = "terraform"
    Project     = "ai-platform"
  }
}
