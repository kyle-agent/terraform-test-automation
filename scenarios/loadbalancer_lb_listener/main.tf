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
# the pool subnet/VPC (409 Conflict). This fixture creates its own LB, so it leaks
# too. Until #77 is fixed the LB lane relies on the API reaper to sweep leaked LBs
# before the pool bootstrap is torn down
# (see docs/findings/loadbalancer-reap-strategy.md).

# LB listener integration fixture (self-contained, like ske_nodepool builds its
# own parent cluster). A listener belongs to a load balancer and (for an L4/TCP
# listener) forwards to a server group, so this scenario provisions the LB + a
# server group + the listener on top.
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
  name        = "rlblvpc${var.name_suffix}"
  cidr        = "192.168.0.0/24"
  description = "regr-test lb listener vpc"
}

resource "samsungcloudplatformv2_vpc_subnet" "regr" {
  name            = "rlblsub${var.name_suffix}"
  vpc_id          = samsungcloudplatformv2_vpc_vpc.regr.id
  type            = "GENERAL"
  cidr            = "192.168.0.0/27"
  description     = "regr-test lb listener subnet"
  dns_nameservers = ["8.8.8.8"]
}

resource "samsungcloudplatformv2_loadbalancer_loadbalancer" "regr" {
  loadbalancer_create = {
    name                     = "rlbl${var.name_suffix}"
    description              = "regression-test-lb"
    layer_type               = "L4"
    firewall_enabled         = false
    firewall_logging_enabled = false
    vpc_id                   = samsungcloudplatformv2_vpc_vpc.regr.id
    subnet_id                = samsungcloudplatformv2_vpc_subnet.regr.id
  }
}

resource "samsungcloudplatformv2_loadbalancer_lb_server_group" "regr" {
  # The API requires a load balancer to already exist in the subnet before a
  # server group can be created there (400: "the chosen subnet does not contain
  # a Load Balancer"). The LB above lives in the same subnet, so order the create.
  depends_on = [samsungcloudplatformv2_loadbalancer_loadbalancer.regr]
  lb_server_group_create = {
    name        = "rlbls${var.name_suffix}"
    description = "regression-test server group"
    protocol    = "TCP"
    lb_method   = "ROUND_ROBIN"
    vpc_id      = samsungcloudplatformv2_vpc_vpc.regr.id
    subnet_id   = samsungcloudplatformv2_vpc_subnet.regr.id
  }
}

resource "samsungcloudplatformv2_loadbalancer_lb_listener" "regr" {
  lb_listener_create = {
    name            = "rlbli${var.name_suffix}"
    description     = "regression-test listener"
    protocol        = "TCP"
    service_port    = 80
    loadbalancer_id = samsungcloudplatformv2_loadbalancer_loadbalancer.regr.id
    server_group_id = samsungcloudplatformv2_loadbalancer_lb_server_group.regr.id
    persistence     = "SOURCE_IP"
    # routing_action enum is {LB_SERVER_GROUP, URL_REDIRECT} (run 27171780178 400);
    # ROUNDROBIN is an lb_method, not a listener routing_action.
    routing_action  = "LB_SERVER_GROUP"
    # L4 listeners require session_duration_time (run 27210071644 400
    # "session_duration_time is required for L4 protocol").
    session_duration_time = 120
  }
}
