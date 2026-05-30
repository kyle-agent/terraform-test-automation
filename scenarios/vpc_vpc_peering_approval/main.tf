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
  description = "Existing VPC peering id to act on. Integration runs override via TF_VAR_vpc_peering_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "approval_type" {
  type        = string
  description = "Peering approval action. Valid: CREATE_APPROVE, CREATE_CANCEL, CREATE_REJECT, CREATE_RE_REQUEST, DELETE_APPROVE, DELETE_CANCEL, DELETE_REJECT."
  default     = "CREATE_APPROVE"
}

# VPC peering approval fixture guarding networking coverage: approving a peering
# request must re-plan cleanly with no spurious update or replacement.
# Required args: type, vpc_peering_id.
resource "samsungcloudplatformv2_vpc_vpc_peering_approval" "regr" {
  type           = var.approval_type
  vpc_peering_id = var.vpc_peering_id
}
