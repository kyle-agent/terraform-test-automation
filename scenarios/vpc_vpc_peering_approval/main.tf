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

# Per-run-unique suffix injected by the harness (TF_VAR_name_suffix).
variable "name_suffix" {
  type        = string
  description = "Per-run unique suffix appended to resource names."
  default     = ""
}

variable "approval_type" {
  type        = string
  description = "Peering approval action. Valid: CREATE_APPROVE, CREATE_CANCEL, CREATE_REJECT, CREATE_RE_REQUEST, DELETE_APPROVE, DELETE_CANCEL, DELETE_REJECT."
  default     = "CREATE_APPROVE"
}

# VPC peering approval fixture guarding networking coverage.
#
# SELF-CONTAINED: relying on an external vpc_peering_id resulted in a 404 (the
# peering never existed). This fixture creates the requester + approver VPCs and
# the peering request in-line (same account), then approves it, so it can
# create -> destroy cleanly.
resource "samsungcloudplatformv2_vpc_vpc" "requester" {
  name        = "regrapvreq${var.name_suffix}"
  cidr        = "192.168.0.0/24"
  description = "regr-test peering-approval requester"
}

resource "samsungcloudplatformv2_vpc_vpc" "approver" {
  name        = "regrapvapp${var.name_suffix}"
  cidr        = "192.168.1.0/24"
  description = "regr-test peering-approval approver"
}

resource "samsungcloudplatformv2_vpc_vpc_peering" "regr" {
  approver_vpc_account_id = samsungcloudplatformv2_vpc_vpc.approver.vpc.account_id
  approver_vpc_id         = samsungcloudplatformv2_vpc_vpc.approver.id
  approver_vpc_name       = "regrapvapp${var.name_suffix}"
  requester_vpc_id        = samsungcloudplatformv2_vpc_vpc.requester.id
  name                    = "regrapv${var.name_suffix}"
  description             = "regr-test"
}

resource "samsungcloudplatformv2_vpc_vpc_peering_approval" "regr" {
  type           = var.approval_type
  vpc_peering_id = samsungcloudplatformv2_vpc_vpc_peering.regr.id
}
