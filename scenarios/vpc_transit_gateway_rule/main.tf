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

variable "transit_gateway_id" {
  type        = string
  description = "Existing transit gateway id owning the routing rule. Integration runs override via TF_VAR_transit_gateway_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "tgw_connection_vpc_id" {
  type        = string
  description = "Existing TGW VPC-connection id the route points at. Integration runs override via TF_VAR_tgw_connection_vpc_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "destination_type" {
  type        = string
  description = "Routing rule destination type. Valid: VPC, TGW."
  default     = "VPC"
}

variable "destination_cidr" {
  type        = string
  description = "Destination CIDR the rule routes to."
  default     = "192.168.32.0/24"
}

# Transit gateway routing rule fixture guarding networking coverage: a VPC route
# on a TGW must re-plan cleanly with no spurious update or replacement.
# Required args: destination_cidr, destination_type, tgw_connection_vpc_id,
# transit_gateway_id. Optional: description.
resource "samsungcloudplatformv2_vpc_transit_gateway_rule" "regr" {
  destination_cidr      = var.destination_cidr
  destination_type      = var.destination_type
  tgw_connection_vpc_id = var.tgw_connection_vpc_id
  transit_gateway_id    = var.transit_gateway_id
  description           = "regr-test"
}
