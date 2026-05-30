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
  description = "Existing VPC id to add the secondary CIDR to. Integration runs override via TF_VAR_vpc_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "cidr" {
  type        = string
  description = "Secondary CIDR block to associate with the VPC."
  default     = "192.168.16.0/24"
}

# VPC secondary-CIDR fixture guarding networking coverage: associating an extra
# CIDR with an existing VPC must re-plan cleanly with no spurious update or
# replacement. Required args: cidr, vpc_id.
resource "samsungcloudplatformv2_vpc_cidr" "regr" {
  cidr   = var.cidr
  vpc_id = var.vpc_id
}
