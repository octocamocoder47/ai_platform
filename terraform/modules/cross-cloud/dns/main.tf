# Cross-Cloud DNS — Route53 ↔ Cloud DNS bidirectional forwarding

data "aws_route53_zone" "private" {
  provider = aws.primary
  zone_id  = var.aws_private_zone_id
}

data "google_dns_managed_zone" "private" {
  provider = google.primary
  name     = var.gcp_private_zone_name
}

# Route53 inbound/outbound resolver endpoints
resource "aws_route53_resolver_endpoint" "inbound" {
  provider = aws.primary

  name                 = "${var.name_prefix}-inbound"
  direction            = "INBOUND"
  security_group_ids   = [var.resolver_sg_id]
  ip_addresses {
    subnet_id = var.resolver_subnet_ids[0]
    ip        = var.resolver_ips[0]
  }
  ip_addresses {
    subnet_id = var.resolver_subnet_ids[1]
    ip        = var.resolver_ips[1]
  }
  tags = var.tags
}

resource "aws_route53_resolver_endpoint" "outbound" {
  provider = aws.primary

  name                 = "${var.name_prefix}-outbound"
  direction            = "OUTBOUND"
  security_group_ids   = [var.resolver_sg_id]
  ip_addresses {
    subnet_id = var.resolver_subnet_ids[0]
    ip        = var.resolver_ips[0]
  }
  ip_addresses {
    subnet_id = var.resolver_subnet_ids[1]
    ip        = var.resolver_ips[1]
  }
  tags = var.tags
}

# Resolver rule to forward GCP DNS queries to Cloud DNS
resource "aws_route53_resolver_rule" "forward_to_gcp" {
  provider = aws.primary

  name                 = "${var.name_prefix}-to-gcp"
  domain_name          = var.gcp_dns_domain
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound.id

  dynamic "target_ip" {
    for_each = var.gcp_dns_ips
    content {
      ip   = target_ip.value
      port = 53
    }
  }
}

resource "aws_route53_resolver_rule_association" "forward_to_gcp" {
  provider = aws.primary

  resolver_rule_id = aws_route53_resolver_rule.forward_to_gcp.id
  vpc_id           = var.aws_vpc_id
}

# Cloud DNS forwarding zone to Route53 (via GCP DNS peering inbound)
resource "google_dns_managed_zone" "forward_to_aws" {
  provider = google.primary

  name        = "${var.name_prefix}-to-aws"
  dns_name    = var.aws_dns_domain
  project     = var.gcp_project_id
  description = "Forwarding zone to AWS Route53 resolver"

  visibility = "private"

  private_visibility_config {
    networks {
      network_url = var.gcp_network_url
    }
  }

  forwarding_config {
    dynamic "target_name_servers" {
      for_each = var.aws_resolver_ips
      content {
        ipv4_address = target_name_servers.value
        forwarding_path = "private"
      }
    }
  }
}
