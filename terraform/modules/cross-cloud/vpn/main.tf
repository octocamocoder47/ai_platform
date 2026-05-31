# =============================================================================
# Cross-Cloud VPN: AWS ↔ GCP
# =============================================================================

# AWS Side
resource "aws_customer_gateway" "gcp" {
  provider = aws.aws-network

  bgp_asn    = var.gcp_bgp_asn
  ip_address = var.gcp_vpn_gateway_ip
  type       = "ipsec.1"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-cgw-gcp"
  })
}

resource "aws_vpn_connection" "cross_cloud" {
  provider = aws.aws-network

  customer_gateway_id = aws_customer_gateway.gcp.id
  transit_gateway_id  = var.aws_tgw_id
  type                = "ipsec.1"

  tunnel1_preshared_key = random_password.tunnel1.result
  tunnel2_preshared_key = random_password.tunnel2.result

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-vpn-to-gcp"
  })
}

resource "random_password" "tunnel1" {
  length  = 32
  special = false
}

resource "random_password" "tunnel2" {
  length  = 32
  special = false
}

# Static routes for GCP CIDRs over VPN
resource "aws_ec2_transit_gateway_route" "gcp" {
  provider = aws.aws-network

  destination_cidr_block         = var.gcp_cidr
  transit_gateway_attachment_id  = aws_vpn_connection.cross_cloud.transit_gateway_attachment_id[0].id
  transit_gateway_route_table_id = var.aws_tgw_route_table_id
}

# GCP Side
resource "google_compute_vpn_gateway" "aws" {
  provider = google.gcp

  name    = "${var.name_prefix}-vpn-to-aws"
  project = var.gcp_project
  region  = var.gcp_region
  network = var.gcp_network
}

resource "google_compute_forwarding_rule" "esp_tunnel1" {
  provider = google.gcp
  name     = "${var.name_prefix}-fr-esp-t1"
  project  = var.gcp_project
  region   = var.gcp_region
  ip_protocol = "ESP"
  ip_address  = google_compute_vpn_gateway.aws.ip_address
  target      = google_compute_vpn_gateway.aws.self_link
}

resource "google_compute_forwarding_rule" "udp500_tunnel1" {
  provider = google.gcp
  name     = "${var.name_prefix}-fr-udp500-t1"
  project  = var.gcp_project
  region   = var.gcp_region
  ip_protocol = "UDP"
  port_range  = "500"
  ip_address  = google_compute_vpn_gateway.aws.ip_address
  target      = google_compute_vpn_gateway.aws.self_link
}

resource "google_compute_forwarding_rule" "udp4500_tunnel1" {
  provider = google.gcp
  name     = "${var.name_prefix}-fr-udp4500-t1"
  project  = var.gcp_project
  region   = var.gcp_region
  ip_protocol = "UDP"
  port_range  = "4500"
  ip_address  = google_compute_vpn_gateway.aws.ip_address
  target      = google_compute_vpn_gateway.aws.self_link
}

resource "google_compute_vpn_tunnel" "tunnel1" {
  provider = google.gcp

  name          = "${var.name_prefix}-tunnel1"
  project       = var.gcp_project
  region        = var.gcp_region
  peer_ip       = aws_vpn_connection.cross_cloud.tunnel1_address
  shared_secret = random_password.tunnel1.result
  target_vpn_gateway = google_compute_vpn_gateway.aws.self_link
  local_traffic_selector  = [var.gcp_cidr]
  remote_traffic_selector = [var.aws_cidr]
  router                  = google_compute_router.aws.name
}

resource "google_compute_router" "aws" {
  provider = google.gcp

  name    = "${var.name_prefix}-router-aws"
  project = var.gcp_project
  region  = var.gcp_region
  network = var.gcp_network

  bgp {
    asn = var.gcp_bgp_asn
  }
}

resource "google_compute_router_interface" "tunnel1" {
  provider = google.gcp

  name       = "${var.name_prefix}-ri-t1"
  project    = var.gcp_project
  region     = var.gcp_region
  router     = google_compute_router.aws.name
  vpn_tunnel = google_compute_vpn_tunnel.tunnel1.name
  ip_range   = aws_vpn_connection.cross_cloud.tunnel1_bgp_peer_address
}

resource "google_compute_router_peer" "bgp_tunnel1" {
  provider = google.gcp

  name                      = "${var.name_prefix}-peer-t1"
  project                   = var.gcp_project
  region                    = var.gcp_region
  router                    = google_compute_router.aws.name
  peer_ip_address           = split("/", aws_vpn_connection.cross_cloud.tunnel1_bgp_peer_address)[0]
  peer_asn                  = aws_vpn_connection.cross_cloud.tunnel1_bgp_asn
  interface                 = google_compute_router_interface.tunnel1.name
  advertised_route_priority = 100
}
