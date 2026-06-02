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

# NOTE: vpc_subnet is intentionally NOT created here — subnet create is broken
# in v3.3.1 (provider bug #59: Value Conversion Error on dns_nameservers). Once
# that is fixed, restore a subnet resource + subnet_id output to unlock the
# subnet-dependent scenarios.

resource "samsungcloudplatformv2_security_group_security_group" "prereq" {
  name        = "rpsg${var.suffix}"
  description = "regr dependent-probe prerequisite security group"
  loggable    = false
}

output "vpc_id" {
  value = samsungcloudplatformv2_vpc_vpc.prereq.id
}

output "security_group_id" {
  value = samsungcloudplatformv2_security_group_security_group.prereq.id
}
