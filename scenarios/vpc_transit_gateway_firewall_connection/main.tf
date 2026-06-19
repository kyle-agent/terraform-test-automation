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
  description = "Existing VPC connected to the TGW. Integration runs override via TF_VAR_vpc_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

# A firewall connection attaches a firewall capability to the TGW. The bootstrap
# exports no TGW, so it is created in-line (a TGW consumes no VPC quota).
#
# REAL ordering (#96, proven by run 27812898493): the firewall_connection create
# 400s "There must be at least one connected VPC to proceed" unless the TGW
# already has a vpc_connection — it is NOT the old "needs a firewall first /
# INACTIVE circular" story (that was a mis-diagnosis). So the chain is
#   TGW -> vpc_connection -> firewall_connection
# and the patched provider waiter (transit_gateway_firewall_connection.go:
# tolerates ATTACHING/INACTIVE, bounded 12-min wait for ACTIVE) carries it to
# ACTIVE. vpc:pool because the vpc_connection needs a real VPC id.
resource "samsungcloudplatformv2_vpc_transit_gateway" "regr" {
  name        = "regr-tgwfwc${var.name_suffix}"
  description = "regr-test"
}

resource "samsungcloudplatformv2_vpc_transit_gateway_vpc_connection" "regr" {
  transit_gateway_id = samsungcloudplatformv2_vpc_transit_gateway.regr.id
  vpc_id             = var.vpc_id
}

resource "samsungcloudplatformv2_vpc_transit_gateway_firewall_connection" "regr" {
  transit_gateway_id = samsungcloudplatformv2_vpc_transit_gateway.regr.id

  depends_on = [samsungcloudplatformv2_vpc_transit_gateway_vpc_connection.regr]
}
