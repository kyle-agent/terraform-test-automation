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

variable "name_suffix" {
  type        = string
  description = "Per-run unique suffix appended to resource names."
  default     = ""
}

variable "product_type" {
  type        = string
  description = "Transit gateway firewall product type. Valid: TGW_IGW, TGW_GGW, TGW_DGW, TGW_BM."
  default     = "TGW_BM"
}

# A firewall needs a transit gateway parent (not exported by the bootstrap), so
# the TGW is created in-line here and the firewall attaches to it. A transit
# gateway consumes no account VPC quota, so this stays within quota.
resource "samsungcloudplatformv2_vpc_transit_gateway" "regr" {
  name        = "regr-tgwfw${var.name_suffix}"
  description = "regr-test"
}

# Transit gateway firewall fixture guarding networking coverage: a firewall
# product attached to a TGW must re-plan cleanly with no spurious update/replace.
# Required args: product_type, transit_gateway_id.
resource "samsungcloudplatformv2_vpc_transit_gateway_firewall" "regr" {
  product_type       = var.product_type
  transit_gateway_id = samsungcloudplatformv2_vpc_transit_gateway.regr.id
}
