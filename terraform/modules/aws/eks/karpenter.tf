# Karpenter IAM Role
resource "aws_iam_role" "karpenter_node" {
  count = var.karpenter_enabled ? 1 : 0
  name  = "${local.cluster_name}-karpenter-node-role"

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

resource "aws_iam_role_policy_attachment" "karpenter_node_worker" {
  count      = var.karpenter_enabled ? 1 : 0
  role       = aws_iam_role.karpenter_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cni" {
  count      = var.karpenter_enabled ? 1 : 0
  role       = aws_iam_role.karpenter_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_registry" {
  count      = var.karpenter_enabled ? 1 : 0
  role       = aws_iam_role.karpenter_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ssm" {
  count      = var.karpenter_enabled ? 1 : 0
  role       = aws_iam_role.karpenter_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Karpenter Instance Profile
resource "aws_iam_instance_profile" "karpenter" {
  count = var.karpenter_enabled ? 1 : 0
  name  = "${local.cluster_name}-karpenter-instance-profile"
  role  = aws_iam_role.karpenter_node[0].name

  tags = var.tags
}

# Karpenter IAM Role for Controller
resource "aws_iam_role" "karpenter_controller" {
  count = var.karpenter_enabled ? 1 : 0
  name  = "${local.cluster_name}-karpenter-controller-role"

  assume_role_policy = data.aws_iam_policy_document.karpenter_assume[0].json

  tags = var.tags
}

data "aws_iam_policy_document" "karpenter_assume" {
  count = var.karpenter_enabled ? 1 : 0

  statement {
    effect = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:karpenter:karpenter"]
    }
  }
}

# Karpenter Controller Policy
data "aws_iam_policy_document" "karpenter_policy" {
  count = var.karpenter_enabled ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "ec2:CreateLaunchTemplate",
      "ec2:CreateFleet",
      "ec2:CreateTags",
      "ec2:DeleteLaunchTemplate",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "iam:PassRole",
      "pricing:GetProducts",
      "ssm:GetParameter",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "karpenter_controller" {
  count  = var.karpenter_enabled ? 1 : 0
  name   = "${local.cluster_name}-karpenter-controller-policy"
  role   = aws_iam_role.karpenter_controller[0].name
  policy = data.aws_iam_policy_document.karpenter_policy[0].json
}
