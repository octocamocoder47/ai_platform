terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

data "google_client_config" "default" {}

# GKE Cluster
resource "google_container_cluster" "main" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.region

  network    = var.vpc_name
  subnetwork = var.subnet_name

  # Private cluster
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # Remove default node pool
  initial_node_count       = 1
  remove_default_node_pool = true

  # Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Addons
  addons_config {
    http_load_balancing {
      disabled = false
    }
    network_policy_config {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  # Network policy (Calico default, can use Cilium)
  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  # Maintenance window
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }

  # Release channel
  release_channel {
    channel = "STABLE"
  }

  # IP allocation policy
  ip_allocation_policy {
    cluster_ipv4_cidr_block  = var.pod_cidr
    services_ipv4_cidr_block = var.service_cidr
  }

  # Default security settings
  pod_security_policy_config {
    enabled = true
  }

  # Shielded nodes
  enable_shielded_nodes = true

  # Binary authorization
  enable_binary_authorization = var.enable_binary_auth

  # Database encryption (CMEK)
  database_encryption {
    state    = "DECRYPTED"
    key_name = ""
  }

  depends_on = [
    google_project_service.container
  ]

  lifecycle {
    ignore_changes = [
      initial_node_count,
      node_pool,
      maintenance_policy,
    ]
  }
}

# Enable required services
resource "google_project_service" "container" {
  project = var.project_id
  service = "container.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "compute" {
  project = var.project_id
  service = "compute.googleapis.com"

  disable_on_destroy = false
}

# Node pools
resource "google_container_node_pool" "system" {
  name     = "${var.cluster_name}-system"
  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.main.name

  initial_node_count = var.system_min_size
  max_pods_per_node  = 32

  autoscaling {
    min_node_count = var.system_min_size
    max_node_count = var.system_max_size
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.system_machine_type
    disk_size_gb = 50
    disk_type    = "pd-standard"

    service_account = google_service_account.nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      "node-type" = "system"
    }

    tags = ["system"]
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}

# GPU node pool (optional)
resource "google_container_node_pool" "gpu" {
  count = var.enable_gpu ? 1 : 0

  name     = "${var.cluster_name}-gpu"
  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.main.name

  initial_node_count = var.gpu_min_size
  max_pods_per_node  = 16

  autoscaling {
    min_node_count = var.gpu_min_size
    max_node_count = var.gpu_max_size
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.gpu_machine_type
    disk_size_gb = 200
    disk_type    = "pd-ssd"

    guest_accelerator {
      type  = var.gpu_type
      count = var.gpu_count
    }

    service_account = google_service_account.nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      "node-type"   = "gpu"
      "accelerator" = var.gpu_type
    }

    tags = ["gpu"]
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}

# Node service account
resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-node-sa"
  display_name = "GKE Node Service Account - ${var.cluster_name}"
}

resource "google_project_iam_member" "nodes_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_project_iam_member" "nodes_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_project_iam_member" "nodes_cr" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}
