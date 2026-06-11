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

# KNOWN ISSUE -- this scenario is registry status=broken. The platform requires a
# load balancer to already exist in the chosen subnet before a health check can be
# created (400: "the chosen subnet does not contain a Load Balancer"). Provisioning
# an LB inside this fixture DOES satisfy that, but in the shared single-subnet pool
# lane it creates a SECOND concurrent LB alongside loadbalancer_lb_member, and the
# two contending LB operations hang terraform for the full 60m go-test budget,
# poisoning the whole shard (run 68 / 27315496017: go-test 60m timeout, no matrix
# produced, leaked LB -> bootstrap subnet teardown 409). Re-enabling needs LB
# scenario isolation (a dedicated subnet per LB scenario, or a serialized LB lane)
# -- see docs/findings/green-56-regression-and-fixes.md. Until then this fixture is
# left in its minimal form (no LB) so `terraform validate` passes offline.

variable "name_suffix" {
  type        = string
  default     = ""
  description = "Per-run unique suffix (injected by the harness as TF_VAR_name_suffix)."
}

variable "vpc_id" {
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
  description = "VPC for the health check. Integration supplies a real id via TF_VAR_vpc_id."
}

variable "subnet_id" {
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
  description = "Subnet for the health check. Integration supplies a real id via TF_VAR_subnet_id."
}

resource "samsungcloudplatformv2_loadbalancer_lb_health_check" "regr" {
  lb_health_check_create = {
    name                  = "rhc${var.name_suffix}"
    description           = "regression-test health check"
    protocol              = "TCP"
    health_check_port     = 80
    health_check_interval = 5
    health_check_timeout  = 5
    health_check_count    = 3
    vpc_id                = var.vpc_id
    subnet_id             = var.subnet_id
  }
}
