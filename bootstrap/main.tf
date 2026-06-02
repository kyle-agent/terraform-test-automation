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
# scenarios can be exercised without TEST_* secrets. The run id keeps names
# unique across runs; the workflow always destroys this stack afterwards.
#
# NOTE: vpc_subnet is intentionally NOT created — subnet create is broken in
# v3.3.1 (provider bug #59: Value Conversion Error on dns_nameservers). Restore
# it once #59 is fixed to unlock the subnet-dependent scenarios.
variable "suffix" {
  type        = string
  description = "Per-run unique suffix (numeric run id)."
  default     = "boot"
}

# Primary VPC (small /24 so vpc_cidr can add a separate, non-overlapping block).
resource "samsungcloudplatformv2_vpc_vpc" "prereq" {
  name        = "rpv${var.suffix}"
  cidr        = "192.168.0.0/24"
  description = "regr dependent-probe prerequisite vpc"
}

# Internet gateway on the primary VPC (some resources, e.g. vpn gateway, require
# the VPC to have an IGW).
resource "samsungcloudplatformv2_vpc_internet_gateway" "prereq" {
  type              = "IGW"
  vpc_id            = samsungcloudplatformv2_vpc_vpc.prereq.id
  description       = "regr dependent-probe prerequisite igw"
  firewall_enabled  = true
  firewall_loggable = false
}

# Subnet — created with dns_nameservers set EXPLICITLY to work around provider
# bug #59 (omitting the Optional+Computed dns_nameservers makes it unknown, which
# the []string model can't hold -> create fails). Setting it makes the value
# known and lets the subnet be created so subnet-dependent scenarios can run.
resource "samsungcloudplatformv2_vpc_subnet" "prereq" {
  name            = "rps${var.suffix}"
  vpc_id          = samsungcloudplatformv2_vpc_vpc.prereq.id
  type            = "GENERAL"
  cidr            = "192.168.0.0/28"
  description     = "regr dependent-probe prerequisite subnet"
  dns_nameservers = ["8.8.8.8", "8.8.4.4"]
}

# Second VPC for peering scenarios (approver side).
resource "samsungcloudplatformv2_vpc_vpc" "prereq2" {
  name        = "rpv2${var.suffix}"
  cidr        = "192.169.0.0/24"
  description = "regr dependent-probe prerequisite vpc 2"
}

resource "samsungcloudplatformv2_security_group_security_group" "prereq" {
  name        = "rpsg${var.suffix}"
  description = "regr dependent-probe prerequisite security group"
  loggable    = false
}

# Public IP (some resources, e.g. vpn gateway, attach to one).
resource "samsungcloudplatformv2_vpc_publicip" "prereq" {
  type        = "IGW"
  description = "regr dependent-probe prerequisite public ip"
}

output "vpc_id" {
  value = samsungcloudplatformv2_vpc_vpc.prereq.id
}

output "approver_vpc_id" {
  value = samsungcloudplatformv2_vpc_vpc.prereq2.id
}

output "subnet_id" {
  value = samsungcloudplatformv2_vpc_subnet.prereq.id
}

output "security_group_id" {
  value = samsungcloudplatformv2_security_group_security_group.prereq.id
}

output "publicip_id" {
  value = samsungcloudplatformv2_vpc_publicip.prereq.id
}

output "publicip_address" {
  value = samsungcloudplatformv2_vpc_publicip.prereq.publicip.ip_address
}
