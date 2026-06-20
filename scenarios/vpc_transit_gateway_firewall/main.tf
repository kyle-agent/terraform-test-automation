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

variable "vpc_id" {
  type        = string
  description = "Existing VPC connected to the TGW (for the vpc_connection the firewall_connection needs). The pool lane injects TF_VAR_vpc_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "product_type" {
  type        = string
  description = "Transit gateway firewall product type. Valid: TGW_IGW, TGW_GGW, TGW_DGW, TGW_BM."
  default     = "TGW_BM"
}

# A firewall needs a transit gateway parent (not exported by the bootstrap), so
# the TGW is created in-line here. A TGW consumes no account VPC quota.
resource "samsungcloudplatformv2_vpc_transit_gateway" "regr" {
  name        = "regr-tgwfw${var.name_suffix}"
  description = "regr-test"
}

# CreateTransitGatewayFirewall 400s "Transit Gateway Firewall connection state is
# not Active (INACTIVE)" unless the TGW already has an ACTIVE firewall connection.
# Build that first: the firewall_connection Create registers the firewall and
# waits ATTACHING -> ACTIVE; its only real prerequisite is a vpc_connection
# (proven by the green firewall_connection scenario + fork PR #99). So the chain
# is TGW -> vpc_connection -> firewall_connection; vpc:pool supplies the vpc_id.
resource "samsungcloudplatformv2_vpc_transit_gateway_vpc_connection" "regr" {
  transit_gateway_id = samsungcloudplatformv2_vpc_transit_gateway.regr.id
  vpc_id             = var.vpc_id
}

resource "samsungcloudplatformv2_vpc_transit_gateway_firewall_connection" "regr" {
  transit_gateway_id = samsungcloudplatformv2_vpc_transit_gateway.regr.id

  depends_on = [samsungcloudplatformv2_vpc_transit_gateway_vpc_connection.regr]
}

# Transit gateway firewall product attached to the (now firewall-active) TGW:
# must re-plan cleanly with no spurious update/replace. Required args:
# product_type, transit_gateway_id.
resource "samsungcloudplatformv2_vpc_transit_gateway_firewall" "regr" {
  product_type       = var.product_type
  transit_gateway_id = samsungcloudplatformv2_vpc_transit_gateway.regr.id

  depends_on = [samsungcloudplatformv2_vpc_transit_gateway_firewall_connection.regr]
}
