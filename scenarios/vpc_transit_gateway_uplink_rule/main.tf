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

variable "destination_type" {
  type        = string
  description = "Uplink rule destination type. Valid: TGW, ON_PREMISE."
  default     = "TGW"
}

variable "destination_cidr" {
  type        = string
  description = "Destination CIDR the uplink rule routes to."
  default     = "192.168.40.0/24"
}

variable "product_type" {
  type        = string
  description = "Transit gateway firewall product type. Valid: TGW_IGW, TGW_GGW, TGW_DGW, TGW_BM."
  default     = "TGW_BM"
}

# An uplink rule needs a transit gateway parent (not exported by the bootstrap),
# so the TGW is created in-line here and the rule attaches to it. A transit
# gateway consumes no account VPC quota, so this stays within quota.
resource "samsungcloudplatformv2_vpc_transit_gateway" "regr" {
  name        = "regr-tgwul${var.name_suffix}"
  description = "regr-test"
}

# An uplink rule can only be created once the TGW has an ACTIVE firewall
# connection (uplink routing is a firewall feature). Build the full prerequisite
# chain: firewall registered on the TGW -> firewall connection (ATTACHING ->
# ACTIVE). The provider's firewall-connection Create waits for ACTIVE, so once
# the connection resource is created the TGW is firewall-active.
resource "samsungcloudplatformv2_vpc_transit_gateway_firewall" "regr" {
  product_type       = var.product_type
  transit_gateway_id = samsungcloudplatformv2_vpc_transit_gateway.regr.id
}

resource "samsungcloudplatformv2_vpc_transit_gateway_firewall_connection" "regr" {
  transit_gateway_id = samsungcloudplatformv2_vpc_transit_gateway.regr.id

  depends_on = [samsungcloudplatformv2_vpc_transit_gateway_firewall.regr]
}

# Transit gateway uplink rule fixture guarding networking coverage: a TGW uplink
# route must re-plan cleanly with no spurious update or replacement.
# Required args: destination_cidr, destination_type, transit_gateway_id.
# Optional: description. depends_on the firewall connection so it is ACTIVE first.
resource "samsungcloudplatformv2_vpc_transit_gateway_uplink_rule" "regr" {
  destination_cidr   = var.destination_cidr
  destination_type   = var.destination_type
  transit_gateway_id = samsungcloudplatformv2_vpc_transit_gateway.regr.id
  description        = "regr-test"

  depends_on = [samsungcloudplatformv2_vpc_transit_gateway_firewall_connection.regr]
}
