# Networking coverage fixture (subnet create -> replan -> destroy).
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

variable "subnet_name" {
  type        = string
  description = "Name of the subnet."
  default     = "regr-subnet"
}

# Per-run-unique suffix injected by the harness (TF_VAR_name_suffix).
variable "name_suffix" {
  type        = string
  description = "Per-run unique suffix appended to resource names."
  default     = ""
}

variable "vpc_id" {
  type        = string
  description = "Existing VPC id to create the subnet in. Integration runs override via TF_VAR_vpc_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "subnet_type" {
  type        = string
  description = "Subnet type."
  default     = "GENERAL"
}

variable "subnet_cidr" {
  type        = string
  description = "CIDR block for the subnet. Must not overlap the bootstrap prereq subnet (192.168.0.0/27) inside the bootstrap VPC (192.168.0.0/24)."
  default     = "192.168.0.64/28"
}

variable "subnet_description" {
  type        = string
  description = "Description for the subnet."
  default     = "regr-test"
}

# Minimal subnet fixture guarding networking coverage: a freshly-created subnet
# must re-plan/re-apply cleanly (no spurious update or destroy+create) when the
# config is unchanged. Required args: cidr, name, type, vpc_id.
#
# dns_nameservers is set EXPLICITLY to work around provider bug #59: leaving the
# Optional+Computed dns_nameservers unset makes it unknown, which the []string
# model can't hold and create fails with a Value Conversion Error. A known value
# avoids that (same workaround the bootstrap prereq subnet uses).
resource "samsungcloudplatformv2_vpc_subnet" "subnet" {
  name            = "${var.subnet_name}${var.name_suffix}"
  vpc_id          = var.vpc_id
  type            = var.subnet_type
  cidr            = var.subnet_cidr
  description     = var.subnet_description
  dns_nameservers = ["8.8.8.8"]
}
