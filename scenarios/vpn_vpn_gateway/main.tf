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
# UUID inputs default to the zero-UUID, overridable via TF_VAR_*; schema-valid
# defaults keep `terraform validate` green offline.

variable "gateway_name" {
  description = "VPN gateway name."
  type        = string
  default     = "regr-vpn-gateway"
}

variable "vpc_id" {
  description = "VPC UUID the VPN gateway attaches to."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "ip_id" {
  description = "Public IP resource UUID assigned to the gateway."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "ip_address" {
  description = "Public IP address of the VPN gateway."
  type        = string
  default     = "10.0.0.10"
}

variable "ip_type" {
  description = "IP allocation type enum (e.g. PUBLIC)."
  type        = string
  default     = "PUBLIC"
}

resource "samsungcloudplatformv2_vpn_vpn_gateway" "regr" {
  name        = var.gateway_name
  vpc_id      = var.vpc_id
  ip_id       = var.ip_id
  ip_address  = var.ip_address
  ip_type     = var.ip_type
  description = "Regression VPN gateway fixture"

  tags = {
    env = "regression"
  }
}
