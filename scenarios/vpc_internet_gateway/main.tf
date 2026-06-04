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

variable "igw_type" {
  type        = string
  description = "Internet gateway type."
  default     = "IGW"
}

# Internet gateway fixture guarding networking coverage.
#
# SELF-CONTAINED: the shared bootstrap VPC already has an Internet Gateway
# attached, so attaching another IGW to it fails with "The VPC is already
# associated with an Internet Gateway". This fixture instead creates its own
# VPC (+ subnet) and attaches the IGW to that, so it can create -> destroy
# cleanly without depending on the bootstrap VPC.
resource "samsungcloudplatformv2_vpc_vpc" "regr" {
  name        = "regrigwvpc${var.name_suffix}"
  cidr        = "192.168.0.0/24"
  description = "regr-test igw vpc"
}

resource "samsungcloudplatformv2_vpc_subnet" "regr" {
  name            = "regrigwsub${var.name_suffix}"
  vpc_id          = samsungcloudplatformv2_vpc_vpc.regr.id
  type            = "GENERAL"
  cidr            = "192.168.0.0/27"
  description     = "regr-test igw subnet"
  dns_nameservers = ["8.8.8.8"]
}

resource "samsungcloudplatformv2_vpc_internet_gateway" "regr" {
  type              = var.igw_type
  vpc_id            = samsungcloudplatformv2_vpc_vpc.regr.id
  description       = "regr-test"
  firewall_enabled  = true
  firewall_loggable = false
}
