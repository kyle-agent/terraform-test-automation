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
  description = "Existing transit gateway id to connect the firewall to. Integration runs override via TF_VAR_transit_gateway_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

# Transit gateway firewall connection fixture guarding networking coverage:
# attaching a firewall to a TGW must re-plan cleanly with no spurious change.
# Required arg: transit_gateway_id.
resource "samsungcloudplatformv2_vpc_transit_gateway_firewall_connection" "regr" {
  transit_gateway_id = var.transit_gateway_id
}
