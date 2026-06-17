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
# parameters. Fully SELF-CONTAINED: it creates its OWN VPC + IGW + subnet +
# public IP + VPN gateway so it does not collide with the sibling
# vpn_vpn_gateway scenario's gateway in the shared bootstrap VPC (the API
# enforces a limit of 1 VPN gateway per VPC: "Exceeded the VPN Gateway limit per
# VPC: 1EA"). The tunnel terminates on the gateway created here. pre_shared_key
# is overridable via TF_VAR_*; schema-valid defaults keep validate green offline.

variable "tunnel_name" {
  description = "VPN tunnel name."
  type        = string
  default     = "regrvpntunnel"
}

variable "gateway_name" {
  description = "VPN gateway name (alphanumeric, <= 20 chars)."
  type        = string
  default     = ""
}

# Per-run-unique suffix injected by the harness (TF_VAR_name_suffix) so a leaked
# resource from a prior run can't collide with this run's create.
variable "name_suffix" {
  description = "Per-run unique suffix appended to resource names."
  type        = string
  default     = ""
}

# The harness actually exports TF_VAR_suffix (= github.run_id); prefer it so the
# names are genuinely unique per run (name_suffix is not injected). Falls back to
# name_suffix, then "".
variable "suffix" {
  description = "Per-run unique suffix injected by the harness as TF_VAR_suffix (github.run_id)."
  type        = string
  default     = ""
}

locals {
  vpn_suffix = var.suffix != "" ? var.suffix : var.name_suffix
  # The suffix (github.run_id) can be >11 digits, which overflows the 3-20 char
  # name limit. Cap it at 11 so the longest prefix below stays within 20.
  vpn_suffix_short = substr(local.vpn_suffix, 0, 11)
  # VPN gateway name rule: <= 20 alphanumeric chars. "regrvpngw" = 9, so cap the
  # suffix at 11 chars to keep the total within 20.
  vpn_gateway_name = var.gateway_name != "" ? var.gateway_name : "regrvpngw${local.vpn_suffix_short}"
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

# Safe in-place-updatable attribute: the provider's UpdateVpnTunnel PATCHes
# Description (Optional, no RequiresReplace). The capability-matrix update stage
# mutates it via update.tfvars.
variable "tunnel_description" {
  description = "VPN tunnel description (in-place updatable)."
  type        = string
  default     = "Regression VPN tunnel fixture"
}

# Dedicated VPC for this scenario so the VPN gateway lives in its own VPC and
# does not hit the per-VPC VPN gateway limit shared with vpn_vpn_gateway.
resource "samsungcloudplatformv2_vpc_vpc" "regr" {
  name        = "rvt${local.vpn_suffix_short}"
  cidr        = "192.168.0.0/24"
  description = "Regression VPN tunnel prereq vpc"
}

# VPN gateway requires the VPC to have an internet gateway.
resource "samsungcloudplatformv2_vpc_internet_gateway" "regr" {
  type              = "IGW"
  vpc_id            = samsungcloudplatformv2_vpc_vpc.regr.id
  description       = "Regression VPN tunnel prereq igw"
  firewall_enabled  = true
  firewall_loggable = false
}

# Subnet in the dedicated VPC (dns_nameservers set explicitly to work around
# provider bug #59).
resource "samsungcloudplatformv2_vpc_subnet" "regr" {
  name            = "rvts${local.vpn_suffix_short}"
  vpc_id          = samsungcloudplatformv2_vpc_vpc.regr.id
  type            = "GENERAL"
  cidr            = "192.168.0.0/27"
  description     = "Regression VPN tunnel prereq subnet"
  dns_nameservers = ["8.8.8.8"]
}

# Dedicated public IP for the VPN gateway (a fresh, unattached public IP keeps
# the gateway create valid).
resource "samsungcloudplatformv2_vpc_publicip" "regr" {
  type        = "IGW"
  description = "Regression VPN gw public IP"
}

resource "samsungcloudplatformv2_vpn_vpn_gateway" "regr" {
  name        = local.vpn_gateway_name
  vpc_id      = samsungcloudplatformv2_vpc_vpc.regr.id
  ip_id       = samsungcloudplatformv2_vpc_publicip.regr.id
  ip_address  = samsungcloudplatformv2_vpc_publicip.regr.publicip.ip_address
  ip_type     = var.ip_type
  description = "Regression VPN gw (tunnel prereq)"

  # Ensure the IGW/subnet exist before the gateway attaches to the VPC.
  depends_on = [
    samsungcloudplatformv2_vpc_internet_gateway.regr,
    samsungcloudplatformv2_vpc_subnet.regr,
  ]

  tags = {
    env = "regression"
  }
}

resource "samsungcloudplatformv2_vpn_vpn_tunnel" "regr" {
  name           = var.tunnel_name
  vpn_gateway_id = samsungcloudplatformv2_vpn_vpn_gateway.regr.id
  description    = var.tunnel_description

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
