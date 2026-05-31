output "vpc_id" {
  description = "VPC self link"
  value       = google_compute_network.main.id
}

output "vpc_self_link" {
  description = "VPC self link"
  value       = google_compute_network.main.self_link
}

output "vpc_name" {
  description = "VPC name"
  value       = google_compute_network.main.name
}

output "subnet_ids" {
  description = "Subnet IDs"
  value       = google_compute_subnetwork.main[*].id
}

output "subnet_self_links" {
  description = "Subnet self links"
  value       = google_compute_subnetwork.main[*].self_link
}

output "nat_router_name" {
  description = "Cloud Router name"
  value       = var.enable_cloud_nat ? google_compute_router.nat[0].name : null
}

output "nat_ip_addresses" {
  description = "NAT IP addresses"
  value       = var.enable_cloud_nat ? google_compute_router_nat.main[0].nat_ip_addresses : []
}
