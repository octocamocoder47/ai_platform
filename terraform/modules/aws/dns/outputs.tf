output "private_zone_id" {
  description = "Private hosted zone ID"
  value       = aws_route53_zone.private.zone_id
}

output "private_zone_name" {
  description = "Private hosted zone name"
  value       = aws_route53_zone.private.name
}

output "private_name_servers" {
  description = "Private zone name servers"
  value       = aws_route53_zone.private.name_servers
}

output "public_zone_id" {
  description = "Public hosted zone ID"
  value       = var.create_public_zone ? aws_route53_zone.public[0].zone_id : null
}

output "public_zone_name" {
  description = "Public hosted zone name"
  value       = var.create_public_zone ? aws_route53_zone.public[0].name : null
}
