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

variable "destination_vpc_type" {
  type        = string
  description = "Side of the peering the route targets. Valid: REQUESTER_VPC, APPROVER_VPC."
  default     = "APPROVER_VPC"
}

variable "destination_cidr" {
  type        = string
  description = "Destination CIDR reachable across the peering."
  default     = "192.168.1.0/24"
}

# VPC peering rule fixture guarding networking coverage.
#
# SELF-CONTAINED: relying on an external vpc_peering_id resulted in a 404 (the
# peering never existed). This fixture creates the requester + approver VPCs,
# the peering request (same account) and its approval in-line, then adds a route
# across it, so it can create -> destroy cleanly. destination_cidr targets the
# approver VPC CIDR to match destination_vpc_type = APPROVER_VPC.
resource "samsungcloudplatformv2_vpc_vpc" "requester" {
  name        = "regrprlreq${var.name_suffix}"
  cidr        = "192.168.0.0/24"
  description = "regr-test peering-rule requester"
}

resource "samsungcloudplatformv2_vpc_vpc" "approver" {
  name        = "regrprlapp${var.name_suffix}"
  cidr        = "192.168.1.0/24"
  description = "regr-test peering-rule approver"
}

resource "samsungcloudplatformv2_vpc_vpc_peering" "regr" {
  approver_vpc_account_id = samsungcloudplatformv2_vpc_vpc.approver.vpc.account_id
  approver_vpc_id         = samsungcloudplatformv2_vpc_vpc.approver.id
  requester_vpc_id        = samsungcloudplatformv2_vpc_vpc.requester.id
  name                    = "regrprl${var.name_suffix}"
  description             = "regr-test"
}

# NO approval resource: same-account peering needs none - the platform rejects
# the approval call outright with 400 "Approval is not required for Same
# Account VPC peering" (peering probe run 27401023616). The peering goes
# CREATING -> ACTIVE on its own (~16 min) and the provider Create waits for
# ACTIVE, so the rule can depend on the peering directly.
resource "samsungcloudplatformv2_vpc_vpc_peering_rule" "regr" {
  destination_cidr     = var.destination_cidr
  destination_vpc_type = var.destination_vpc_type
  vpc_peering_id       = samsungcloudplatformv2_vpc_vpc_peering.regr.id
}
