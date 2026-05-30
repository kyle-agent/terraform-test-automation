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

variable "vpc_id" {
  type        = string
  description = "Existing VPC id to attach the internet gateway to. Integration runs override via TF_VAR_vpc_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "igw_type" {
  type        = string
  description = "Internet gateway type."
  default     = "IGW"
}

# Internet gateway fixture guarding networking coverage: an IGW attached to a VPC
# must re-plan cleanly with no spurious update or replacement.
# Required args: type, vpc_id. Optional: description, firewall_enabled, tags.
resource "samsungcloudplatformv2_vpc_internet_gateway" "regr" {
  type              = var.igw_type
  vpc_id            = var.vpc_id
  description       = "regr-test"
  firewall_enabled  = true
  firewall_loggable = false
}
