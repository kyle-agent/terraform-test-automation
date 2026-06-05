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

# Promoted regression fixture: a Direct Connect routing rule pointing at a VPC
# CIDR. Self-contained: it creates its own prerequisite Direct Connect (bound to
# the bootstrap VPC via TF_VAR_vpc_id) and the routing rule belongs to that
# parent. schema-valid defaults keep `terraform validate` green offline.

variable "direct_connect_name" {
  description = "Direct Connect name."
  type        = string
  default     = "regr-direct-connect"
}

variable "bandwidth" {
  description = "Direct Connect bandwidth. Must be one of 1, 10, 20, 40."
  type        = number
  default     = 1
}

variable "destination_cidr" {
  description = "Destination CIDR block the rule routes traffic toward."
  type        = string
  default     = "10.0.0.0/24"
}

variable "destination_type" {
  description = "Destination resource type enum (e.g. VPC)."
  type        = string
  default     = "VPC"
}

# When destination_type is VPC, the API requires the target VPC's resource id.
# Bound to the bootstrap VPC at apply via TF_VAR_vpc_id; defaults to the
# zero-UUID so the fixture validates offline.
variable "vpc_id" {
  description = "Destination VPC resource id (required when destination_type is VPC)."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

resource "samsungcloudplatformv2_directconnect_direct_connect" "regr" {
  bandwidth         = var.bandwidth
  name              = var.direct_connect_name
  vpc_id            = var.vpc_id
  description       = "Regression DC fixture (routing rule)"
  firewall_enabled  = true
  firewall_loggable = false

  tags = {
    env = "regression"
  }
}

resource "samsungcloudplatformv2_directconnect_routing_rule" "regr" {
  direct_connect_id       = samsungcloudplatformv2_directconnect_direct_connect.regr.id
  destination_cidr        = var.destination_cidr
  destination_type        = var.destination_type
  destination_resource_id = var.vpc_id
  description             = "Regression routing rule fixture"
}
