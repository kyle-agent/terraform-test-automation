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
# CIDR. direct_connect_id defaults to the zero-UUID, overridable via TF_VAR_*;
# schema-valid defaults keep `terraform validate` green offline.

variable "direct_connect_id" {
  description = "Direct Connect UUID this routing rule belongs to."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
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

resource "samsungcloudplatformv2_directconnect_routing_rule" "regr" {
  direct_connect_id = var.direct_connect_id
  destination_cidr  = var.destination_cidr
  destination_type  = var.destination_type
  description       = "Regression routing rule fixture"
}
