output "terraform_state_bucket" {
  description = "Terraform state bucket name"
  value       = google_storage_bucket.terraform_state.name
}

output "model_storage_bucket" {
  description = "Model storage bucket name"
  value       = google_storage_bucket.model_storage.name
}

output "backup_bucket" {
  description = "Backup bucket name"
  value       = google_storage_bucket.backups.name
}
