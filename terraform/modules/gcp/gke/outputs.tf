output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.main.name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.main.endpoint
}

output "cluster_ca_cert" {
  description = "GKE cluster CA certificate"
  value       = google_container_cluster.main.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "GKE cluster location"
  value       = google_container_cluster.main.location
}

output "node_service_account" {
  description = "GKE node service account"
  value       = google_service_account.nodes.email
}

output "workload_identity_pool" {
  description = "Workload Identity pool"
  value       = "${var.project_id}.svc.id.goog"
}
