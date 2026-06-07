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

# Self-contained private-NAT fixture. A private NAT attaches to a "service
# resource" (a transit gateway) which the bootstrap does not provide, so we
# create the transit gateway here and point the private NAT at it. No VPC is
# consumed by a transit gateway, so this stays within the account VPC quota.
variable "name_suffix" {
  type        = string
  description = "Per-run unique suffix appended to resource names."
  default     = ""
}

variable "private_nat_name" {
  type        = string
  description = "Name of the private NAT."
  default     = "regr-pnat"
}

variable "private_nat_cidr" {
  type        = string
  description = "IP range allocated to the private NAT."
  default     = "192.168.64.0/24"
}

variable "service_type" {
  type        = string
  description = "Connected service type for the private NAT. Valid: TRANSIT_GATEWAY, DIRECT_CONNECT."
  default     = "TRANSIT_GATEWAY"
}

# Parent transit gateway acting as the private NAT service resource.
resource "samsungcloudplatformv2_vpc_transit_gateway" "regr" {
  name        = "regr-pn-tgw${var.name_suffix}"
  description = "regr-test"
}

# Private NAT bound to the transit gateway (top-level id used for chaining).
resource "samsungcloudplatformv2_vpc_private_nat" "regr" {
  cidr                = var.private_nat_cidr
  name                = "${var.private_nat_name}${var.name_suffix}"
  service_resource_id = samsungcloudplatformv2_vpc_transit_gateway.regr.id
  service_type        = var.service_type
  description         = "regr-test"
}
