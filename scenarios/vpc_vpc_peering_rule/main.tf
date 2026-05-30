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

variable "vpc_peering_id" {
  type        = string
  description = "Existing VPC peering id owning the rule. Integration runs override via TF_VAR_vpc_peering_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "destination_vpc_type" {
  type        = string
  description = "Side of the peering the route targets. Valid: REQUESTER_VPC, APPROVER_VPC."
  default     = "APPROVER_VPC"
}

variable "destination_cidr" {
  type        = string
  description = "Destination CIDR reachable across the peering."
  default     = "192.168.48.0/24"
}

# VPC peering rule fixture guarding networking coverage: a route across an
# established peering must re-plan cleanly with no spurious update or replace.
# Required args: destination_cidr, destination_vpc_type, vpc_peering_id.
# Optional: tags.
resource "samsungcloudplatformv2_vpc_vpc_peering_rule" "regr" {
  destination_cidr     = var.destination_cidr
  destination_vpc_type = var.destination_vpc_type
  vpc_peering_id       = var.vpc_peering_id
}
