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
  description = "Existing transit gateway id to attach the VPC to. Integration runs override via TF_VAR_transit_gateway_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "vpc_id" {
  type        = string
  description = "Existing VPC id to connect to the transit gateway. Integration runs override via TF_VAR_vpc_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

# Transit gateway VPC connection fixture guarding networking coverage: attaching
# a VPC to a TGW must re-plan cleanly with no spurious update or replacement.
# Required args: transit_gateway_id, vpc_id.
resource "samsungcloudplatformv2_vpc_transit_gateway_vpc_connection" "regr" {
  transit_gateway_id = var.transit_gateway_id
  vpc_id             = var.vpc_id
}
