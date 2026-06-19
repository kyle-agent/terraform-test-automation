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

# A firewall connection attaches a firewall capability to the TGW. The bootstrap
# exports no TGW, so it is created in-line (a TGW consumes no VPC quota).
#
# CONNECTION-FIRST experiment (#96): earlier fixtures created a firewall first,
# but firewall.Create itself 400s "connection state is not Active (INACTIVE)"
# unless the connection is already ACTIVE — a circular trap. This fixture instead
# creates ONLY the connection on the TGW and relies on the patched provider waiter
# (transit_gateway_firewall_connection.go: tolerates ATTACHING/INACTIVE, bounded
# 12-min wait for ACTIVE) to determine whether POST /firewall-connections
# self-activates without a firewall present. If it does, the TGW firewall family
# is fixture-orderable; if it times out at INACTIVE, the circular dependency is a
# platform limitation (and the bounded waiter at least fails fast, not in 2h).
resource "samsungcloudplatformv2_vpc_transit_gateway" "regr" {
  name        = "regr-tgwfwc${var.name_suffix}"
  description = "regr-test"
}

resource "samsungcloudplatformv2_vpc_transit_gateway_firewall_connection" "regr" {
  transit_gateway_id = samsungcloudplatformv2_vpc_transit_gateway.regr.id
}
