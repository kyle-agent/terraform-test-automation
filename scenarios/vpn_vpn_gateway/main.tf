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

# Promoted regression fixture: a VPN gateway bound to a VPC and a public IP.
# SELF-CONTAINED: it creates its OWN VPC + internet gateway + public IP so the
# VPN gateway create always finds an attached Internet Gateway on the VPC
# (the API returns "404 Cannot found the Internet Gateway on VPC" otherwise) and
# so it never collides with the sibling vpn_vpn_tunnel scenario's gateway (the
# API enforces a limit of 1 VPN gateway per VPC). var.vpc_id / var.ip_id /
# var.ip_address remain as optional overrides for targeted runs.

# The harness exports TF_VAR_suffix (= github.run_id); append it so the gateway
# name is unique per run and leaked "regr*" gateways from prior runs can't
# collide. VPN gateway name rule: <= 20 alphanumeric chars, so use a short base
# ("regrvpngw" = 9) and truncate the suffix to keep total <= 20.
variable "suffix" {
  description = "Per-run unique suffix injected by the harness as TF_VAR_suffix (github.run_id)."
  type        = string
  default     = ""
}

variable "gateway_name" {
  description = "VPN gateway name (alphanumeric, <= 20 chars)."
  type        = string
  default     = ""
}

locals {
  # Cap the suffix at 11 chars so the longest name below stays within the limit.
  vpn_suffix_short = substr(var.suffix, 0, 11)
  vpn_gateway_name = var.gateway_name != "" ? var.gateway_name : "regrvpngw${local.vpn_suffix_short}"

  # Use the supplied override VPC/IP when set, otherwise the resources created
  # below. The zero-UUID default means "not supplied".
  zero_uuid     = "00000000-0000-0000-0000-000000000000"
  vpc_id        = var.vpc_id != local.zero_uuid ? var.vpc_id : samsungcloudplatformv2_vpc_vpc.regr.id
  publicip_id   = var.ip_id != local.zero_uuid ? var.ip_id : samsungcloudplatformv2_vpc_publicip.regr.id
  publicip_addr = var.ip_id != local.zero_uuid ? var.ip_address : samsungcloudplatformv2_vpc_publicip.regr.publicip.ip_address
}

variable "vpc_id" {
  description = "VPC UUID the VPN gateway attaches to (override; default creates its own VPC)."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "ip_id" {
  description = "Public IP resource UUID assigned to the gateway (override; default creates its own public IP)."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "ip_address" {
  description = "Public IP address of the VPN gateway (only used with var.ip_id)."
  type        = string
  default     = "10.0.0.10"
}

variable "ip_type" {
  description = "IP allocation type enum (e.g. PUBLIC)."
  type        = string
  default     = "PUBLIC"
}

# Safe in-place-updatable attribute: the provider's UpdateVpnGateway PATCHes
# Description (Optional, no RequiresReplace). The capability-matrix update stage
# mutates it via update.tfvars.
variable "gateway_description" {
  description = "VPN gateway description (in-place updatable)."
  type        = string
  default     = "Regression VPN gateway fixture"
}

# Dedicated VPC for this scenario so the VPN gateway lives in its own VPC.
resource "samsungcloudplatformv2_vpc_vpc" "regr" {
  name        = "rvg${local.vpn_suffix_short}"
  cidr        = "192.168.0.0/24"
  description = "Regression VPN gateway prereq vpc"
}

# VPN gateway requires the VPC to have an internet gateway.
resource "samsungcloudplatformv2_vpc_internet_gateway" "regr" {
  type              = "IGW"
  vpc_id            = samsungcloudplatformv2_vpc_vpc.regr.id
  description       = "Regression VPN gateway prereq igw"
  firewall_enabled  = true
  firewall_loggable = false
}

# Subnet in the dedicated VPC (dns_nameservers set explicitly to work around
# provider bug #59).
resource "samsungcloudplatformv2_vpc_subnet" "regr" {
  name            = "rvgs${local.vpn_suffix_short}"
  vpc_id          = samsungcloudplatformv2_vpc_vpc.regr.id
  type            = "GENERAL"
  cidr            = "192.168.0.0/27"
  description     = "Regression VPN gateway prereq subnet"
  dns_nameservers = ["8.8.8.8"]
}

# Dedicated public IP for the VPN gateway.
resource "samsungcloudplatformv2_vpc_publicip" "regr" {
  type        = "IGW"
  description = "Regression VPN gw public IP"
}

resource "samsungcloudplatformv2_vpn_vpn_gateway" "regr" {
  name        = local.vpn_gateway_name
  vpc_id      = local.vpc_id
  ip_id       = local.publicip_id
  ip_address  = local.publicip_addr
  ip_type     = var.ip_type
  description = var.gateway_description

  # The IGW must exist/attach to the VPC before the VPN gateway is created.
  depends_on = [
    samsungcloudplatformv2_vpc_internet_gateway.regr,
    samsungcloudplatformv2_vpc_subnet.regr,
  ]

  tags = {
    env = "regression"
  }
}
