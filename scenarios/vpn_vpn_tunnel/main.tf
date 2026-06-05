terraform {
  required_version = ">= 1.6"
  required_providers {
    samsungcloudplatformv2 = {
      source  = "SamsungSDSCloud/samsungcloudplatformv2"
      version = ">= 0.0.1"
    }
  }
}

provider "samsungcloudplatformv2" {}

# Promoted regression fixture: a VPN tunnel with full IKE phase1/phase2 IPsec
# parameters. Self-contained: it creates its own prerequisite VPN gateway (bound
# to the bootstrap VPC / public IP via TF_VAR_*) and the tunnel terminates on
# that gateway. pre_shared_key is overridable via TF_VAR_*; schema-valid
# defaults keep validate green offline.

variable "tunnel_name" {
  description = "VPN tunnel name."
  type        = string
  default     = "regrvpntunnel"
}

variable "gateway_name" {
  description = "VPN gateway name (alphanumeric, 3-20 chars)."
  type        = string
  default     = "regrvpngateway"
}

variable "vpc_id" {
  description = "VPC UUID the VPN gateway attaches to."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "ip_type" {
  description = "IP allocation type enum (e.g. PUBLIC)."
  type        = string
  default     = "PUBLIC"
}

variable "peer_gateway_ip" {
  description = "Remote (peer) gateway public IP address."
  type        = string
  default     = "10.0.0.20"
}

variable "pre_shared_key" {
  description = "IPsec pre-shared key for the tunnel."
  type        = string
  sensitive   = true
  default     = "regr-pre-shared-key"
}

variable "remote_subnets" {
  description = "Remote (peer) subnets reachable through the tunnel."
  type        = list(string)
  default     = ["10.0.0.0/24"]
}

# Create a dedicated public IP for the VPN gateway. Reusing the bootstrap public
# IP (var.ip_id) fails because that IP is already ATTACHED; a fresh, unattached
# public IP keeps the gateway create valid.
resource "samsungcloudplatformv2_vpc_publicip" "regr" {
  type        = "IGW"
  description = "Regression VPN gw public IP"
}

resource "samsungcloudplatformv2_vpn_vpn_gateway" "regr" {
  name        = var.gateway_name
  vpc_id      = var.vpc_id
  ip_id       = samsungcloudplatformv2_vpc_publicip.regr.id
  ip_address  = samsungcloudplatformv2_vpc_publicip.regr.publicip.ip_address
  ip_type     = var.ip_type
  description = "Regression VPN gw (tunnel prereq)"

  tags = {
    env = "regression"
  }
}

resource "samsungcloudplatformv2_vpn_vpn_tunnel" "regr" {
  name           = var.tunnel_name
  vpn_gateway_id = samsungcloudplatformv2_vpn_vpn_gateway.regr.id
  description    = "Regression VPN tunnel fixture"

  phase1 = {
    ike_version                  = 2
    peer_gateway_ip              = var.peer_gateway_ip
    phase1_diffie_hellman_groups = [14]
    phase1_encryptions           = ["aes256"]
    phase1_life_time             = 86400
    pre_shared_key               = var.pre_shared_key
    dpd_retry_interval           = 30
  }

  phase2 = {
    perfect_forward_secrecy      = "ENABLE"
    phase2_diffie_hellman_groups = [14]
    phase2_encryptions           = ["aes256"]
    phase2_life_time             = 3600
    remote_subnets               = var.remote_subnets
  }

  tags = {
    env = "regression"
  }
}
