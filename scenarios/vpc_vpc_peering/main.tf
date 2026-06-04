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

variable "peering_name" {
  type        = string
  description = "VPC peering name (3-20 chars, [a-zA-Z0-9-])."
  default     = "regrpeering"
}

# VPC peering fixture guarding networking coverage.
#
# SELF-CONTAINED: relying on external requester/approver VPC ids resulted in a
# 404 (the peer VPCs never existed). This fixture creates both the requester and
# approver VPCs in-line and peers them in the SAME account (approver account id
# is read off the created approver VPC), so it can create -> destroy cleanly.
resource "samsungcloudplatformv2_vpc_vpc" "requester" {
  name        = "regrpeerreq${var.name_suffix}"
  cidr        = "192.168.0.0/24"
  description = "regr-test peering requester"
}

resource "samsungcloudplatformv2_vpc_vpc" "approver" {
  name        = "regrpeerapp${var.name_suffix}"
  cidr        = "192.168.1.0/24"
  description = "regr-test peering approver"
}

resource "samsungcloudplatformv2_vpc_vpc_peering" "regr" {
  approver_vpc_account_id = samsungcloudplatformv2_vpc_vpc.approver.vpc.account_id
  approver_vpc_id         = samsungcloudplatformv2_vpc_vpc.approver.id
  requester_vpc_id        = samsungcloudplatformv2_vpc_vpc.requester.id
  name                    = "${var.peering_name}${var.name_suffix}"
  description             = "regr-test"
}
