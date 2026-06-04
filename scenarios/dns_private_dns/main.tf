# DNS private-zone coverage fixture (create -> replan -> destroy).
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

# Per-run-unique suffix injected by the harness (TF_VAR_name_suffix) so a leaked
# resource from a prior run can't collide with this run's create.
variable "name_suffix" {
  type        = string
  description = "Per-run unique suffix appended to resource names."
  default     = ""
}

# Real VPC id supplied by the dependent-probe bootstrap via TF_VAR_vpc_id.
# Defaults to the zero-UUID so the fixture validates offline.
variable "vpc_id" {
  type        = string
  description = "Existing VPC id to connect the private DNS zone to. Integration overrides via TF_VAR_vpc_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "private_dns_name" {
  type        = string
  description = "Name of the private DNS zone."
  default     = "regr-private-dns"
}

# DNS private DNS regression fixture. The resource takes a single nested object
# attribute `private_dns_create`. connected_vpc_ids is bound to the bootstrap
# VPC so the zone attaches to a real VPC at apply; a second apply with no config
# change must re-plan cleanly.
resource "samsungcloudplatformv2_dns_private_dns" "regr" {
  private_dns_create = {
    description       = "regression-test private DNS"
    name              = "${var.private_dns_name}${var.name_suffix}"
    connected_vpc_ids = [var.vpc_id]
  }
}
