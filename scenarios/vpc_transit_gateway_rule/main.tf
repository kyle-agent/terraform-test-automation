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

# Self-contained transit-gateway routing-rule fixture. A routing rule needs a TGW
# and a VPC attached to it (the rule's tgw_connection_vpc_id is the connected VPC
# id). The bootstrap exports neither a TGW nor a TGW-VPC connection, so we build
# the full chain here: transit gateway -> VPC connection (bootstrap VPC) ->
# routing rule. A transit gateway consumes no account VPC quota.
variable "name_suffix" {
  type        = string
  description = "Per-run unique suffix appended to resource names."
  default     = ""
}

variable "vpc_id" {
  type        = string
  description = "Existing VPC id connected to the TGW and targeted by the route. Integration runs override via TF_VAR_vpc_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "destination_type" {
  type        = string
  description = "Routing rule destination type. Valid: VPC, TGW."
  default     = "VPC"
}

variable "destination_cidr" {
  type        = string
  description = "Destination CIDR the rule routes to (the connected VPC's CIDR)."
  default     = "192.168.0.0/24"
}

resource "samsungcloudplatformv2_vpc_transit_gateway" "regr" {
  name        = "regr-tgwr${var.name_suffix}"
  description = "regr-test"
}

resource "samsungcloudplatformv2_vpc_transit_gateway_vpc_connection" "regr" {
  transit_gateway_id = samsungcloudplatformv2_vpc_transit_gateway.regr.id
  vpc_id             = var.vpc_id
}

# Route on the TGW toward the connected VPC. depends_on the connection so the VPC
# is attached before the rule references it.
resource "samsungcloudplatformv2_vpc_transit_gateway_rule" "regr" {
  destination_cidr      = var.destination_cidr
  destination_type      = var.destination_type
  tgw_connection_vpc_id = var.vpc_id
  transit_gateway_id    = samsungcloudplatformv2_vpc_transit_gateway.regr.id
  description           = "regr-test"

  depends_on = [samsungcloudplatformv2_vpc_transit_gateway_vpc_connection.regr]
}
