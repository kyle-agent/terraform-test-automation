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

# Self-contained transit-gateway VPC-connection fixture. The connection needs a
# transit gateway parent (not exported by the bootstrap), so the TGW is created
# here and the bootstrap VPC (TF_VAR_vpc_id) is attached to it. A transit gateway
# does not consume the account VPC quota, so this stays within quota.
variable "name_suffix" {
  type        = string
  description = "Per-run unique suffix appended to resource names."
  default     = ""
}

variable "vpc_id" {
  type        = string
  description = "Existing VPC id to connect to the transit gateway. Integration runs override via TF_VAR_vpc_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

resource "samsungcloudplatformv2_vpc_transit_gateway" "regr" {
  name        = "regr-tgwc${var.name_suffix}"
  description = "regr-test"
}

# TGW create waits for ACTIVE before returning, so the connection can attach
# immediately. The connection in turn waits for its own ACTIVE state.
resource "samsungcloudplatformv2_vpc_transit_gateway_vpc_connection" "regr" {
  transit_gateway_id = samsungcloudplatformv2_vpc_transit_gateway.regr.id
  vpc_id             = var.vpc_id
}
