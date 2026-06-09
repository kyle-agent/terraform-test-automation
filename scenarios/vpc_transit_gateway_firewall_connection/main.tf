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

# A firewall connection attaches the TGW's firewall to the TGW, so both a transit
# gateway and a firewall on it must exist first. The bootstrap exports neither, so
# the full chain (TGW -> firewall -> firewall connection) is built in-line here. A
# transit gateway consumes no account VPC quota, so this stays within quota.
resource "samsungcloudplatformv2_vpc_transit_gateway" "regr" {
  name        = "regr-tgwfwc${var.name_suffix}"
  description = "regr-test"
}

# Firewall registered on the TGW; the connection below attaches it (ATTACHING ->
# ACTIVE). Without a firewall present the connection can never reach ACTIVE.
resource "samsungcloudplatformv2_vpc_transit_gateway_firewall" "regr" {
  product_type       = var.product_type
  transit_gateway_id = samsungcloudplatformv2_vpc_transit_gateway.regr.id
}

# Transit gateway firewall connection fixture guarding networking coverage:
# attaching a firewall to a TGW must re-plan cleanly with no spurious change.
# Required arg: transit_gateway_id. depends_on the firewall so it is registered
# before the connection waits for ATTACHING -> ACTIVE.
resource "samsungcloudplatformv2_vpc_transit_gateway_firewall_connection" "regr" {
  transit_gateway_id = samsungcloudplatformv2_vpc_transit_gateway.regr.id

  depends_on = [samsungcloudplatformv2_vpc_transit_gateway_firewall.regr]
}
