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

variable "requester_vpc_id" {
  type        = string
  description = "Requester-side VPC id. Integration runs override via TF_VAR_requester_vpc_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "approver_vpc_id" {
  type        = string
  description = "Approver-side VPC id. Integration runs override via TF_VAR_approver_vpc_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "approver_vpc_account_id" {
  type        = string
  description = "Account id owning the approver VPC. Integration runs override via TF_VAR_approver_vpc_account_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "peering_name" {
  type        = string
  description = "VPC peering name (3-20 chars, [a-zA-Z0-9-])."
  default     = "regr-peering"
}

# VPC peering fixture guarding networking coverage: a peering request between two
# VPCs must re-plan cleanly with no spurious update or replacement.
# Required args: approver_vpc_account_id, approver_vpc_id, name,
# requester_vpc_id. Optional: description, tags.
resource "samsungcloudplatformv2_vpc_vpc_peering" "regr" {
  approver_vpc_account_id = var.approver_vpc_account_id
  approver_vpc_id         = var.approver_vpc_id
  name                    = var.peering_name
  requester_vpc_id        = var.requester_vpc_id
  description             = "regr-test"
}
