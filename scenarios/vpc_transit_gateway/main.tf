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

variable "tgw_name" {
  type        = string
  description = "Name of the transit gateway (3-20 chars, [a-zA-Z0-9-])."
  default     = "regr-tgw"
}

# Transit gateway fixture guarding networking coverage: a freshly-created TGW
# must re-plan/re-apply cleanly with no spurious update or destroy+create.
# Required arg: name. Optional: description, tags.
resource "samsungcloudplatformv2_vpc_transit_gateway" "regr" {
  name        = var.tgw_name
  description = "regr-test"
}
