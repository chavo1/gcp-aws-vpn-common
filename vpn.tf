#VPN CONFIGURATION
#===================================

# Attach a VPN gateway to the VPC.
resource "google_compute_vpn_gateway" "target_gateway" {
  name    = "vpn-gateway"
  network = var.vpc
  region  = var.region
}

# Forward IPSec traffic coming into our static IP to our VPN gateway.
resource "google_compute_forwarding_rule" "fr_esp" {
  name        = "fr-esp"
  region      = var.region
  ip_protocol = "ESP"
  ip_address  = var.vpn_gw_ip
  target      = google_compute_vpn_gateway.target_gateway.self_link
}

# The following two sets of forwarding rules are used as a part of the IPSec
# protocol
resource "google_compute_forwarding_rule" "fr_udp500" {
  name        = "fr-udp500"
  region      = var.region
  ip_protocol = "UDP"
  port_range  = "500"
  ip_address  = var.vpn_gw_ip
  target      = google_compute_vpn_gateway.target_gateway.self_link

}

resource "google_compute_forwarding_rule" "fr_udp4500" {
  name        = "fr-udp4500"
  region      = var.region
  ip_protocol = "UDP"
  port_range  = "4500"
  ip_address  = var.vpn_gw_ip
  target      = google_compute_vpn_gateway.target_gateway.self_link
}

# Each tunnel is responsible for encrypting and decrypting traffic exiting
# and leaving its associated gateway
# We will create 2 tunnels to aws on same GCP VPN gateway
resource "google_compute_vpn_tunnel" "tunnel1" {
  name               = "aws-tunnel1"
  region             = var.region
  peer_ip            = var.tunnel1_address
  ike_version        = "1"
  shared_secret      = var.preshared_key
  target_vpn_gateway = google_compute_vpn_gateway.target_gateway.self_link

  local_traffic_selector = [
    var.subnet_range,
    var.subnet_range
  ]
  remote_traffic_selector = [
    var.remote_cidr
  ]

  depends_on = [google_compute_forwarding_rule.fr_udp500,
    google_compute_forwarding_rule.fr_udp4500,
    google_compute_forwarding_rule.fr_esp,
  ]
}

resource "google_compute_vpn_tunnel" "tunnel2" {
  name               = "aws-tunnel2"
  region             = var.region
  peer_ip            = var.tunnel2_address
  ike_version        = "1"
  shared_secret      = var.preshared_key
  target_vpn_gateway = google_compute_vpn_gateway.target_gateway.self_link

  local_traffic_selector = [
    var.subnet_range,
    var.subnet_range
  ]
  remote_traffic_selector = [
    var.remote_cidr
  ]

  depends_on = [google_compute_forwarding_rule.fr_udp500,
    google_compute_forwarding_rule.fr_udp4500,
    google_compute_forwarding_rule.fr_esp,
  ]
}

# Create GCE route to AWS network via the VPN tunnel1
# Two routes are created - one for each of the vpn tunnels
# to the 2 AWS headends

# route through tunnel 1 takes precedence with lower priority
resource "google_compute_route" "aws_tunnel1_route" {
  name                = "aws-tunnel1-route"
  dest_range          = "172.31.16.0/22"
  network             = var.vpc
  next_hop_vpn_tunnel = google_compute_vpn_tunnel.tunnel1.self_link
  priority            = 90
}

resource "google_compute_route" "aws_tunnel2_route" {
  name                = "aws-tunnel2-route"
  dest_range          = "172.31.16.0/22"
  network             = var.vpc
  next_hop_vpn_tunnel = google_compute_vpn_tunnel.tunnel2.self_link
  priority            = 100
}
