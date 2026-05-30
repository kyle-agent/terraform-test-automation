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

variable "service_resource_id" {
  type        = string
  description = "Id of the service resource (e.g. transit gateway) the private NAT connects to. Integration runs override via TF_VAR_service_resource_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "service_type" {
  type        = string
  description = "Connected service type for the private NAT. Valid: TRANSIT_GATEWAY, DIRECT_CONNECT."
  default     = "TRANSIT_GATEWAY"
}

variable "private_nat_name" {
  type        = string
  description = "Name of the private NAT."
  default     = "regr-private-nat"
}

variable "private_nat_cidr" {
  type        = string
  description = "IP range allocated to the private NAT."
  default     = "192.168.64.0/24"
}

# Private NAT fixture guarding networking coverage: a private NAT bound to a
# service resource must re-plan cleanly with no spurious update or replacement.
# Required args: cidr, name, service_resource_id, service_type.
# Optional: description, tags.
resource "samsungcloudplatformv2_vpc_private_nat" "regr" {
  cidr                = var.private_nat_cidr
  name                = var.private_nat_name
  service_resource_id = var.service_resource_id
  service_type        = var.service_type
  description         = "regr-test"
}
