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

# Shared prerequisites created once per dependent-probe run, so the dependent
# scenarios (subnet, port, nat gateway, vpc endpoint, vpn gateway, ...) can be
# exercised without TEST_* secrets. The run id keeps names unique across runs;
# the workflow always destroys this stack afterwards.
variable "suffix" {
  type        = string
  description = "Per-run unique suffix (numeric run id)."
  default     = "boot"
}

resource "samsungcloudplatformv2_vpc_vpc" "prereq" {
  name        = "rpv${var.suffix}"
  cidr        = "192.168.0.0/16"
  description = "regr dependent-probe prerequisite vpc"
}

resource "samsungcloudplatformv2_vpc_subnet" "prereq" {
  name        = "rps${var.suffix}"
  vpc_id      = samsungcloudplatformv2_vpc_vpc.prereq.id
  type        = "GENERAL"
  cidr        = "192.168.10.0/24"
  description = "regr dependent-probe prerequisite subnet"
}

resource "samsungcloudplatformv2_security_group_security_group" "prereq" {
  name        = "rpsg${var.suffix}"
  description = "regr dependent-probe prerequisite security group"
  loggable    = false
}

output "vpc_id" {
  value = samsungcloudplatformv2_vpc_vpc.prereq.id
}

output "subnet_id" {
  value = samsungcloudplatformv2_vpc_subnet.prereq.id
}

output "security_group_id" {
  value = samsungcloudplatformv2_security_group_security_group.prereq.id
}
