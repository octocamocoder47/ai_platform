terraform {
  required_version = ">= 1.9.0"
}

locals {
  name_prefix = var.name_prefix != "" ? var.name_prefix : "ai-platform"
  zone_name   = var.zone_name != "" ? var.zone_name : "${local.name_prefix}.${var.environment}.internal"
}

# Private Hosted Zone
resource "aws_route53_zone" "private" {
  name = local.zone_name
  vpc {
    vpc_id = var.vpc_id
  }
  comment = "Private DNS zone for ${local.name_prefix} ${var.environment}"

  tags = merge(var.tags, {
    Name = local.zone_name
  })
}

# Public Hosted Zone (for external endpoints)
resource "aws_route53_zone" "public" {
  count = var.create_public_zone ? 1 : 0

  name   = var.public_zone_name != "" ? var.public_zone_name : "${local.name_prefix}.example.com"
  comment = "Public DNS zone for ${local.name_prefix} ${var.environment}"

  tags = merge(var.tags, {
    Name = var.public_zone_name
  })
}

# A Records for internal services
resource "aws_route53_record" "argocd" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "argocd.${local.zone_name}"
  type    = "A"
  ttl     = 60
  records = [var.internal_lb_ip]
}

resource "aws_route53_record" "grafana" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "grafana.${local.zone_name}"
  type    = "A"
  ttl     = 60
  records = [var.internal_lb_ip]
}

resource "aws_route53_record" "hubble" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "hubble.${local.zone_name}"
  type    = "A"
  ttl     = 60
  records = [var.internal_lb_ip]
}

resource "aws_route53_record" "vault" {
  count  = var.enable_vault ? 1 : 0
  zone_id = aws_route53_zone.private.zone_id
  name    = "vault.${local.zone_name}"
  type    = "A"
  ttl     = 60
  records = [var.internal_lb_ip]
}

# NS Records for cross-account delegation
resource "aws_route53_record" "ns_delegation" {
  for_each = var.delegate_to_accounts != {} ? var.delegate_to_accounts : {}

  zone_id = aws_route53_zone.private.zone_id
  name    = each.key
  type    = "NS"
  ttl     = 300
  records = each.value.name_servers
}
