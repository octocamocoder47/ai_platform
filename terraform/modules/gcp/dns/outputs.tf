output "private_zone_id" {
  description = "Private DNS zone ID"
  value       = google_dns_managed_zone.private.id
}

output "private_zone_name" {
  description = "Private DNS zone name"
  value       = google_dns_managed_zone.private.dns_name
}

output "private_zone_name_servers" {
  description = "Private zone name servers"
  value       = google_dns_managed_zone.private.name_servers
}
