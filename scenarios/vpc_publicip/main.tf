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

variable "publicip_description" {
  type        = string
  description = "Description for the public IP."
  default     = "regr-test"
}

variable "publicip_type" {
  type        = string
  description = "Public IP gateway type. Valid: IGW, GGW, SIGW."
  default     = "IGW"
}

# Minimal public IP fixture guarding networking coverage: a freshly-created
# public IP must re-plan/re-apply cleanly (no spurious update or destroy+create)
# when the config is unchanged. Required arg: type. Optional: description, tags.
resource "samsungcloudplatformv2_vpc_publicip" "publicip" {
  description = var.publicip_description
  type        = var.publicip_type
}
