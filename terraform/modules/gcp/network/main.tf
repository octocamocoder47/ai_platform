terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

data "google_project" "current" {
  project_id = var.project_id
}

# Shared VPC Host (if enabled)
resource "google_compute_shared_vpc_host_project" "shared_vpc" {
  count      = var.enable_shared_vpc ? 1 : 0
  project    = var.project_id
}

# VPC
resource "google_compute_network" "main" {
  name                    = var.vpc_name
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [google_compute_shared_vpc_host_project.shared_vpc]

  lifecycle {
    prevent_destroy = false
  }
}

# Subnets
resource "google_compute_subnetwork" "main" {
  count = length(var.subnet_cidrs)

  name          = "${var.vpc_name}-subnet-${count.index}"
  project       = var.project_id
  network       = google_compute_network.main.id
  region        = var.region
  ip_cidr_range = var.subnet_cidrs[count.index]
  private_ip_google_access = true
}

# Cloud NAT
resource "google_compute_router" "nat" {
  count   = var.enable_cloud_nat ? 1 : 0
  name    = "${var.vpc_name}-nat-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.main.id

  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "main" {
  count   = var.enable_cloud_nat ? 1 : 0
  name    = "${var.vpc_name}-nat"
  project = var.project_id
  region  = var.region
  router  = google_compute_router.nat[0].name

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# VPC Peering (for spoke attachment)
resource "google_compute_network_peering" "spoke" {
  count        = var.peer_vpc != null ? 1 : 0
  name         = "${var.vpc_name}-peering-to-spoke"
  network      = google_compute_network.main.id
  peer_network = var.peer_vpc
}

# Firewall Rules
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.vpc_name}-allow-internal"
  project = var.project_id
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = var.subnet_cidrs
}

resource "google_compute_firewall" "allow_health_checks" {
  name    = "${var.vpc_name}-allow-health-checks"
  project = var.project_id
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }

  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22",
    "209.85.152.0/22",
    "209.85.204.0/22",
  ]
}
