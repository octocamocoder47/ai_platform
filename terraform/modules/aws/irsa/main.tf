terraform {
  required_version = ">= 1.9.0"
}

locals {
  cluster_name = var.cluster_name

  # Build service account key -> namespace/name mapping
  sa_map = { for k, v in var.service_accounts : k => {
    namespace = try(split("/", k)[0], "default")
    name      = try(split("/", k)[1], k)
  }}
}

data "aws_iam_policy_document" "assume_role" {
  for_each = var.service_accounts

  statement {
    effect = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${local.sa_map[each.key].namespace}:${local.sa_map[each.key].name}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# Create IAM roles from inline policies
resource "aws_iam_role" "irsa" {
  for_each = { for k, v in var.service_accounts : k => v if v.policy != null }

  name               = "${local.cluster_name}-${replace(each.key, "/", "-")}"
  assume_role_policy = data.aws_iam_policy_document.assume_role[each.key].json

  tags = merge(var.tags, {
    ServiceAccount = each.key
  })
}

resource "aws_iam_role_policy" "irsa" {
  for_each = { for k, v in var.service_accounts : k => v if v.policy != null }

  name   = "${local.cluster_name}-${replace(each.key, "/", "-")}-policy"
  role   = aws_iam_role.irsa[each.key].name
  policy = each.value.policy
}

# Create IAM roles from managed policy ARNs
resource "aws_iam_role" "irsa_managed" {
  for_each = { for k, v in var.service_accounts : k => v if v.policy_arns != null }

  name               = "${local.cluster_name}-${replace(each.key, "/", "-")}"
  assume_role_policy = data.aws_iam_policy_document.assume_role[each.key].json

  tags = merge(var.tags, {
    ServiceAccount = each.key
  })
}

resource "aws_iam_role_policy_attachment" "irsa_managed" {
  for_each = { for k, v in var.service_accounts : k => v if v.policy_arns != null }

  role       = aws_iam_role.irsa_managed[each.key].name
  policy_arn = each.value.policy_arns
}

# Store role ARN -> service account mapping for use by Helm charts
output "irsa_roles" {
  description = "IRSA role ARNs by service account"
  value = merge(
    { for k, v in aws_iam_role.irsa : k => v.arn },
    { for k, v in aws_iam_role.irsa_managed : k => v.arn }
  )
}
