terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

resource "google_dns_managed_zone" "private" {
  name        = "${var.name_prefix}-private-zone"
  dns_name    = var.dns_name
  project     = var.project_id
  description = "Private DNS zone for ${var.name_prefix}"

  visibility = "private"

  private_visibility_config {
    networks {
      network_url = var.network_url
    }
  }
}

resource "google_dns_record_set" "gke_ingress" {
  for_each = var.ingress_records

  name         = "${each.key}.${var.dns_name}"
  type         = "A"
  ttl          = 60
  managed_zone = google_dns_managed_zone.private.name
  project      = var.project_id
  rrdatas      = [each.value]
}

resource "google_dns_record_set" "gke_svc" {
  for_each = var.service_records

  name         = "${each.key}.${var.dns_name}"
  type         = "A"
  ttl          = 60
  managed_zone = google_dns_managed_zone.private.name
  project      = var.project_id
  rrdatas      = [each.value]
}

# Cloud DNS peering for cross-cloud connectivity
resource "google_dns_managed_zone" "peering_zone" {
  count = var.peer_with_aws ? 1 : 0

  name        = "${var.name_prefix}-aws-peering"
  dns_name    = var.aws_dns_name
  project     = var.project_id
  description = "Peering zone for AWS private DNS resolution"

  visibility = "private"

  private_visibility_config {
    networks {
      network_url = var.network_url
    }
  }

  peering_config {
    target_network {
      network_url = var.peer_network_url
    }
  }
}
