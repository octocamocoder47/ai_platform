# IAM Role for EKS Node Groups
resource "aws_iam_role" "node" {
  count = var.node_role_arn == "" ? 1 : 0
  name  = "${local.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  count      = var.node_role_arn == "" ? 1 : 0
  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  count      = var.node_role_arn == "" ? 1 : 0
  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_registry" {
  count      = var.node_role_arn == "" ? 1 : 0
  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_ssm" {
  count      = var.node_role_arn == "" ? 1 : 0
  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# System Node Group
resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.cluster_name}-system"
  node_role_arn   = var.node_role_arn != "" ? var.node_role_arn : aws_iam_role.node[0].arn
  subnet_ids      = var.subnet_ids
  version         = var.cluster_version

  instance_types = var.system_instance_types
  disk_size      = 50

  scaling_config {
    desired_size = var.system_min_size
    min_size     = var.system_min_size
    max_size     = var.system_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = merge({
    "node.kubernetes.io/role" = "system"
    "node-type"               = "system"
  }, var.system_labels)

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-system"
    "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
    "k8s.io/cluster-autoscaler/enabled"               = "true"
  })

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [scaling_config[0].desired_size, version]
  }
}

# Managed GPU Node Groups (if defined)
resource "aws_eks_node_group" "gpu" {
  for_each = var.gpu_node_groups

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.cluster_name}-${each.key}"
  node_role_arn   = var.node_role_arn != "" ? var.node_role_arn : aws_iam_role.node[0].arn
  subnet_ids      = var.subnet_ids
  version         = var.cluster_version

  instance_types = each.value.instance_types
  disk_size      = each.value.disk_size

  capacity_type = each.value.spot ? "SPOT" : "ON_DEMAND"

  scaling_config {
    desired_size = each.value.min_size
    min_size     = each.value.min_size
    max_size     = each.value.max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = merge({
    "node.kubernetes.io/role" = each.key
    "node-type"               = each.key
    "accelerator"             = each.value.accelerator
    "nvidia.com/gpu"          = "true"
  }, each.value.labels)

  taint {
    key    = "nvidia.com/gpu"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  tags = merge(var.tags, {
    Name = "${local.cluster_name}-${each.key}"
    "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
    "k8s.io/cluster-autoscaler/enabled"               = "true"
  })

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [scaling_config[0].desired_size, version]
  }
}
