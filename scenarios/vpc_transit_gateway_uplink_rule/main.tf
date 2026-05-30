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
  description = "Existing transit gateway id owning the uplink rule. Integration runs override via TF_VAR_transit_gateway_id."
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

# Transit gateway uplink rule fixture guarding networking coverage: a TGW uplink
# route must re-plan cleanly with no spurious update or replacement.
# Required args: destination_cidr, destination_type, transit_gateway_id.
# Optional: description.
resource "samsungcloudplatformv2_vpc_transit_gateway_uplink_rule" "regr" {
  destination_cidr   = var.destination_cidr
  destination_type   = var.destination_type
  transit_gateway_id = var.transit_gateway_id
  description        = "regr-test"
}
