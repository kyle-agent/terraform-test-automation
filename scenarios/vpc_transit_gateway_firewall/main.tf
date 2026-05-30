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
  description = "Existing transit gateway id to attach the firewall to. Integration runs override via TF_VAR_transit_gateway_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "product_type" {
  type        = string
  description = "Transit gateway firewall product type. Valid: TGW_IGW, TGW_GGW, TGW_DGW, TGW_BM."
  default     = "TGW_BM"
}

# Transit gateway firewall fixture guarding networking coverage: a firewall
# product attached to a TGW must re-plan cleanly with no spurious update/replace.
# Required args: product_type, transit_gateway_id.
resource "samsungcloudplatformv2_vpc_transit_gateway_firewall" "regr" {
  product_type       = var.product_type
  transit_gateway_id = var.transit_gateway_id
}
