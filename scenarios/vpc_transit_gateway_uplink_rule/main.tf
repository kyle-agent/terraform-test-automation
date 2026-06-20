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

# An uplink rule needs a transit gateway parent (not exported by the bootstrap),
# so the TGW is created in-line here. A TGW consumes no account VPC quota.
resource "samsungcloudplatformv2_vpc_transit_gateway" "regr" {
  name        = "regr-tgwul${var.name_suffix}"
  description = "regr-test"
}

# An uplink rule can only be created once the TGW has an ACTIVE firewall
# connection. The firewall_connection Create registers the firewall itself and
# waits ATTACHING -> ACTIVE; its only real prerequisite is a vpc_connection
# (proven by the green vpc_transit_gateway_firewall_connection scenario + fork
# PR #99). So the chain is TGW -> vpc_connection -> firewall_connection; vpc:pool
# supplies a real vpc_id for the connection.
resource "samsungcloudplatformv2_vpc_transit_gateway_vpc_connection" "regr" {
  transit_gateway_id = samsungcloudplatformv2_vpc_transit_gateway.regr.id
  vpc_id             = var.vpc_id
}

resource "samsungcloudplatformv2_vpc_transit_gateway_firewall_connection" "regr" {
  transit_gateway_id = samsungcloudplatformv2_vpc_transit_gateway.regr.id

  depends_on = [samsungcloudplatformv2_vpc_transit_gateway_vpc_connection.regr]
}

# Transit gateway uplink rule: a TGW uplink route must re-plan cleanly with no
# spurious update or replacement. Required args: destination_cidr,
# destination_type, transit_gateway_id. depends_on the firewall connection so it
# is ACTIVE first.
resource "samsungcloudplatformv2_vpc_transit_gateway_uplink_rule" "regr" {
  destination_cidr   = var.destination_cidr
  destination_type   = var.destination_type
  transit_gateway_id = samsungcloudplatformv2_vpc_transit_gateway.regr.id
  description        = "regr-test"

  depends_on = [samsungcloudplatformv2_vpc_transit_gateway_firewall_connection.regr]
}
