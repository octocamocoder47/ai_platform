output "aws_inbound_endpoint_id" {
  value = aws_route53_resolver_endpoint.inbound.id
}

output "aws_outbound_endpoint_id" {
  value = aws_route53_resolver_endpoint.outbound.id
}

output "gcp_forwarding_zone_name" {
  value = var.aws_dns_domain != "" ? google_dns_managed_zone.forward_to_aws[0].name : null
}
