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
# vpc/subnet (independent of a load balancer until a listener references it), so
# this scenario is self-contained: it only needs vpc_id/subnet_id from the
# dependent-probe bootstrap (TF_VAR_*). The resource takes a single nested object
# `lb_server_group_create`. lb_health_check_id is optional and omitted to keep the
# fixture minimal. All inputs have offline-safe defaults so `terraform validate`
# passes without credentials.

variable "name_suffix" {
  type        = string
  default     = ""
  description = "Per-run unique suffix (injected by the harness as TF_VAR_name_suffix)."
}

variable "vpc_id" {
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
  description = "VPC for the server group. Integration supplies a real id via TF_VAR_vpc_id."
}

variable "subnet_id" {
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
  description = "Subnet for the server group. Integration supplies a real id via TF_VAR_subnet_id."
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
    vpc_id                   = var.vpc_id
    subnet_id                = var.subnet_id
  }
}

resource "samsungcloudplatformv2_loadbalancer_lb_server_group" "regr" {
  depends_on = [samsungcloudplatformv2_loadbalancer_loadbalancer.regr]
  lb_server_group_create = {
    name        = "rlbgs${var.name_suffix}"
    description = "regression-test server group"
    protocol    = "TCP"
    lb_method   = "ROUND_ROBIN"
    vpc_id      = var.vpc_id
    subnet_id   = var.subnet_id
  }
}
