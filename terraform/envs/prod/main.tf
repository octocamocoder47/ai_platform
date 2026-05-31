# Production environment — HA, multi-AZ, larger scale
# Uses the same modules as dev but with production variables

module "network" {
  source = "../../modules/aws/network"

  name_prefix         = "ai-platform"
  environment         = "prod"
  region              = "us-east-1"
  vpc_cidr            = "10.20.0.0/16"
  azs                 = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnets      = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
  private_system_subnets  = ["10.20.10.0/24", "10.20.11.0/24", "10.20.12.0/24"]
  private_gpu_subnets     = ["10.20.20.0/24", "10.20.21.0/24", "10.20.22.0/24"]
  enable_nat_gateway  = true
  single_nat_gateway  = false
  enable_transit_gateway = true
  enable_flow_logs    = true
  flow_logs_retention = 90
  tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
    Project     = "ai-platform"
    CostCenter  = "platform-engineering"
  }
}

module "eks" {
  source = "../../modules/aws/eks"

  name_prefix    = "ai-platform"
  environment    = "prod"
  cluster_version = "1.31"
  vpc_id         = module.network.vpc_id
  vpc_cidr       = module.network.vpc_cidr
  subnet_ids     = module.network.private_system_subnet_ids

  system_instance_types = ["t3.large"]
  system_min_size       = 3
  system_max_size       = 10

  gpu_node_groups = {
    gpu-inference = {
      instance_types = ["g5.xlarge"]
      min_size       = 3
      max_size       = 20
      accelerator    = "nvidia-tesla-t4"
      spot           = false
    }
    gpu-batch = {
      instance_types = ["p5.48xlarge"]
      min_size       = 0
      max_size       = 5
      accelerator    = "nvidia-h100"
      spot           = true
    }
  }

  karpenter_enabled = true
  tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
    Project     = "ai-platform"
  }
}
