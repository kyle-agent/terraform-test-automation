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

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC."
  default     = "192.167.0.0/18"
}

variable "vpc_description" {
  type        = string
  description = "Description for the VPC."
  default     = "regr-test"
}

variable "vpc_name" {
  type        = string
  description = "Name of the VPC."
  default     = "regr-vpc"
}

# Minimal VPC fixture guarding networking coverage: a freshly-created VPC must
# re-plan/re-apply cleanly (no spurious update or destroy+create) when the
# config is unchanged. Required args: cidr, name. Optional: description, tags.
resource "samsungcloudplatformv2_vpc_vpc" "vpc" {
  cidr        = var.vpc_cidr
  description = var.vpc_description
  name        = var.vpc_name
}
