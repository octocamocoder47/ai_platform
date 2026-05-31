terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# GCS Bucket for Terraform State
resource "google_storage_bucket" "terraform_state" {
  name          = "${var.project_id}-tfstate"
  project       = var.project_id
  location      = var.region
  storage_class = "STANDARD"

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = var.kms_key_name
  }

  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      num_newer_versions = 10
    }
    action {
      type = "Delete"
    }
  }
}

# GCS Bucket for Model Storage
resource "google_storage_bucket" "model_storage" {
  name          = "${var.project_id}-models"
  project       = var.project_id
  location      = var.region
  storage_class = "STANDARD"

  versioning {
    enabled = true
  }

  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
}

# GCS Bucket for Backups
resource "google_storage_bucket" "backups" {
  name          = "${var.project_id}-backups"
  project       = var.project_id
  location      = var.region
  storage_class = "NEARLINE"

  versioning {
    enabled = true
  }

  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
}

# Public access prevention
resource "google_storage_bucket_iam_member" "deny_public" {
  for_each = toset([
    google_storage_bucket.terraform_state.name,
    google_storage_bucket.model_storage.name,
    google_storage_bucket.backups.name,
  ])

  bucket = each.value
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.storage_admin_sa}"
}
