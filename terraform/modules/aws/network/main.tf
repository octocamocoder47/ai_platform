terraform {
  required_version = ">= 1.9.0"
}

locals {
  name_prefix = var.name_prefix != "" ? var.name_prefix : "ai-platform"
  env         = var.environment
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-vpc"
  })
}

# Public Subnets
resource "aws_subnet" "public" {
  count = length(var.public_subnets)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                                          = "${local.name_prefix}-${local.env}-public-${var.azs[count.index]}"
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.name_prefix}-${local.env}" = "shared"
  })
}

# Private Subnets — System
resource "aws_subnet" "private_system" {
  count = length(var.private_system_subnets)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_system_subnets[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, {
    Name                                          = "${local.name_prefix}-${local.env}-private-system-${var.azs[count.index]}"
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.name_prefix}-${local.env}" = "shared"
  })
}

# Private Subnets — GPU Inference
resource "aws_subnet" "private_gpu" {
  count = length(var.private_gpu_subnets)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_gpu_subnets[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-private-gpu-${var.azs[count.index]}"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-igw"
  })
}

# NAT Gateway (one per AZ)
resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(var.azs)) : 0
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-nat-eip-${count.index}"
  })
}

resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(var.azs)) : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-nat-${count.index}"
  })

  depends_on = [aws_internet_gateway.main]
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-public-rt"
  })
}

resource "aws_route_table" "private" {
  count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(var.azs)) : 0

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-private-rt-${count.index}"
  })
}

# Route table associations
resource "aws_route_table_association" "public" {
  count = length(var.public_subnets)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_system" {
  count = length(var.private_system_subnets)

  subnet_id      = aws_subnet.private_system[count.index].id
  route_table_id = aws_route_table.private[var.single_nat_gateway ? 0 : count.index].id
}

resource "aws_route_table_association" "private_gpu" {
  count = length(var.private_gpu_subnets)

  subnet_id      = aws_subnet.private_gpu[count.index].id
  route_table_id = aws_route_table.private[var.single_nat_gateway ? 0 : count.index].id
}

# Transit Gateway
resource "aws_ec2_transit_gateway" "main" {
  count = var.enable_transit_gateway ? 1 : 0

  description = "${local.name_prefix}-${local.env}-tgw"

  amazon_side_asn                 = var.tgw_asn
  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-tgw"
  })
}

# RAM share for TGW
resource "aws_ram_resource_share" "tgw" {
  count = var.enable_transit_gateway ? 1 : 0

  name                      = "${local.name_prefix}-${local.env}-tgw-share"
  allow_external_principals = false

  permission_arns = ["arn:aws:ram::aws:permission/AWSRAMPermissionTransitGateway"]

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-tgw-share"
  })
}

resource "aws_ram_resource_association" "tgw" {
  count = var.enable_transit_gateway ? 1 : 0

  resource_share_arn = aws_ram_resource_share.tgw[0].arn
  resource_arn       = aws_ec2_transit_gateway.main[0].arn
}

resource "aws_ram_principal_association" "tgw" {
  count = var.enable_transit_gateway ? length(var.tgw_share_accounts) : 0

  resource_share_arn = aws_ram_resource_share.tgw[0].arn
  principal          = var.tgw_share_accounts[count.index]
}

# VPC Endpoints (Gateway type)
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id
  )

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-vpce-s3"
  })
}

# VPC Endpoints (Interface type)
locals {
  interface_endpoints = {
    ecr_api  = "com.amazonaws.${var.region}.ecr.api"
    ecr_dkr  = "com.amazonaws.${var.region}.ecr.dkr"
    sts      = "com.amazonaws.${var.region}.sts"
    secretsmgr = "com.amazonaws.${var.region}.secretsmanager"
    monitoring = "com.amazonaws.${var.region}.monitoring"
    logs     = "com.amazonaws.${var.region}.logs"
    ec2      = "com.amazonaws.${var.region}.ec2"
    kms      = "com.amazonaws.${var.region}.kms"
    dynamodb = "com.amazonaws.${var.region}.dynamodb"
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = { for k, v in local.interface_endpoints : k => v }

  vpc_id              = aws_vpc.main.id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_system[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-vpce-${each.key}"
  })
}

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "${local.name_prefix}-${local.env}-vpce-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-vpce-sg"
  })
}

# Flow Logs
resource "aws_flow_log" "main" {
  count = var.enable_flow_logs ? 1 : 0

  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${local.env}-flow-logs"
  })
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "${local.name_prefix}-${local.env}-vpc-flow-logs"
  retention_in_days = var.flow_logs_retention

  tags = var.tags
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${local.name_prefix}-${local.env}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${local.name_prefix}-${local.env}-flow-logs-policy"
  role = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}
