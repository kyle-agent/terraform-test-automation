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

# KNOWN ISSUE -- provider #77 (LB destroy-leak): load balancers APPLY and REPLAN
# cleanly but LEAK on destroy, and the leaked LB blocks teardown of the pool
# subnet/VPC (409 Conflict). This scenario is the confirmed leaker. Until #77 is
# fixed the LB lane relies on the API reaper to sweep leaked LBs before the pool
# bootstrap is torn down (see docs/findings/loadbalancer-reap-strategy.md).

# Load balancer (the resource itself) integration fixture.
# Guards: a loadbalancer creates cleanly, a subsequent re-plan is idempotent
# (no spurious diff / replacement), and it destroys cleanly.
# The resource takes a single nested object attribute `loadbalancer_create`.
#
# SELF-CONTAINED: the platform allows only ONE load balancer per subnet and
# rejects a 2nd create while the 1st is still CREATING (409), so LB scenarios
# cannot share one pool subnet. This fixture creates its OWN VPC + subnet and
# wires the LB to them via computed refs. name carries the per-run suffix to
# avoid cross-run collisions. All inputs have offline-safe defaults so
# `terraform validate` passes without credentials.

variable "name_suffix" {
  type        = string
  default     = ""
  description = "Per-run unique suffix (injected by the harness as TF_VAR_name_suffix)."
}

# In-place-updatable LB description (loadbalancer_create.description is Optional, no
# RequiresReplace; the provider's UpdateLoadbalancer PATCHes only this field). The
# capability-matrix update stage overrides it via update.tfvars; the default keeps
# create + offline validate unchanged.
variable "lb_description" {
  type        = string
  default     = "regression-test-lb"
  description = "Load balancer description (in-place updatable)."
}

resource "samsungcloudplatformv2_vpc_vpc" "regr" {
  name        = "rlbbvpc${var.name_suffix}"
  cidr        = "192.168.0.0/24"
  description = "regr-test lb vpc"
}

resource "samsungcloudplatformv2_vpc_subnet" "regr" {
  name            = "rlbbsub${var.name_suffix}"
  vpc_id          = samsungcloudplatformv2_vpc_vpc.regr.id
  type            = "GENERAL"
  cidr            = "192.168.0.0/27"
  description     = "regr-test lb subnet"
  dns_nameservers = ["8.8.8.8"]
}

resource "samsungcloudplatformv2_loadbalancer_loadbalancer" "regr" {
  loadbalancer_create = {
    name                     = "rlbb${var.name_suffix}"
    description              = var.lb_description
    layer_type               = "L4"
    firewall_enabled         = false
    firewall_logging_enabled = false
    vpc_id                   = samsungcloudplatformv2_vpc_vpc.regr.id
    subnet_id                = samsungcloudplatformv2_vpc_subnet.regr.id
  }
}
