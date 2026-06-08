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

# KNOWN ISSUE -- provider #77 (LB destroy-leak): load balancer family resources
# APPLY and REPLAN cleanly but LEAK on destroy, and a leaked LB blocks teardown of
# the pool subnet/VPC (409 Conflict). Until #77 is fixed the LB lane relies on the
# API reaper to sweep leaked LBs before the pool bootstrap is torn down
# (see docs/findings/loadbalancer-reap-strategy.md).

# LB server group integration fixture. A server group binds directly to a
# vpc/subnet (independent of a load balancer until a listener references it).
# The resource takes a single nested object `lb_server_group_create`.
# lb_health_check_id is optional and omitted to keep the fixture minimal.
#
# SELF-CONTAINED: the platform allows only ONE load balancer per subnet and
# rejects a 2nd create while the 1st is still CREATING (409), so LB scenarios
# cannot share one pool subnet. This fixture creates its OWN VPC + subnet and
# wires the LB / server group to them via computed refs. All inputs have
# offline-safe defaults so `terraform validate` passes without credentials.

variable "name_suffix" {
  type        = string
  default     = ""
  description = "Per-run unique suffix (injected by the harness as TF_VAR_name_suffix)."
}

resource "samsungcloudplatformv2_vpc_vpc" "regr" {
  name        = "rlbgvpc${var.name_suffix}"
  cidr        = "192.168.0.0/24"
  description = "regr-test lb server group vpc"
}

resource "samsungcloudplatformv2_vpc_subnet" "regr" {
  name            = "rlbgsub${var.name_suffix}"
  vpc_id          = samsungcloudplatformv2_vpc_vpc.regr.id
  type            = "GENERAL"
  cidr            = "192.168.0.0/27"
  description     = "regr-test lb server group subnet"
  dns_nameservers = ["8.8.8.8"]
}

# The API requires a load balancer to already exist in the subnet before a
# server group can be created there (live 400: "the chosen subnet does not
# contain a Load Balancer ... Please ensure a Load Balancer exists within the
# subnet before attempting again."). So this fixture provisions its own LB in
# the same subnet first, then the server group on top.
resource "samsungcloudplatformv2_loadbalancer_loadbalancer" "regr" {
  loadbalancer_create = {
    name                     = "rlbg${var.name_suffix}"
    description              = "regression-test-lb"
    layer_type               = "L4"
    firewall_enabled         = false
    firewall_logging_enabled = false
    vpc_id                   = samsungcloudplatformv2_vpc_vpc.regr.id
    subnet_id                = samsungcloudplatformv2_vpc_subnet.regr.id
  }
}

resource "samsungcloudplatformv2_loadbalancer_lb_server_group" "regr" {
  depends_on = [samsungcloudplatformv2_loadbalancer_loadbalancer.regr]
  lb_server_group_create = {
    name        = "rlbgs${var.name_suffix}"
    description = "regression-test server group"
    protocol    = "TCP"
    lb_method   = "ROUND_ROBIN"
    vpc_id      = samsungcloudplatformv2_vpc_vpc.regr.id
    subnet_id   = samsungcloudplatformv2_vpc_subnet.regr.id
  }
}
