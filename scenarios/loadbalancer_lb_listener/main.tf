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

# LB listener integration fixture (self-contained, like ske_nodepool builds its
# own parent cluster). A listener belongs to a load balancer and (for an L4/TCP
# listener) forwards to a server group, so this scenario provisions the LB + a
# server group + the listener on top. Only vpc_id/subnet_id come from the
# dependent-probe bootstrap (TF_VAR_*). All inputs have offline-safe defaults so
# `terraform validate` passes without credentials.

variable "name_suffix" {
  type        = string
  default     = ""
  description = "Per-run unique suffix (injected by the harness as TF_VAR_name_suffix)."
}

variable "vpc_id" {
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
  description = "VPC for the load balancer / server group. Integration supplies a real id via TF_VAR_vpc_id."
}

variable "subnet_id" {
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
  description = "Subnet for the load balancer / server group. Integration supplies a real id via TF_VAR_subnet_id."
}

resource "samsungcloudplatformv2_loadbalancer_loadbalancer" "regr" {
  loadbalancer_create = {
    name                     = "rlb${var.name_suffix}"
    description              = "regression-test-lb"
    layer_type               = "L4"
    firewall_enabled         = false
    firewall_logging_enabled = false
    vpc_id                   = var.vpc_id
    subnet_id                = var.subnet_id
  }
}

resource "samsungcloudplatformv2_loadbalancer_lb_server_group" "regr" {
  lb_server_group_create = {
    name        = "rsg${var.name_suffix}"
    description = "regression-test server group"
    protocol    = "TCP"
    lb_method   = "ROUND_ROBIN"
    vpc_id      = var.vpc_id
    subnet_id   = var.subnet_id
  }
}

resource "samsungcloudplatformv2_loadbalancer_lb_listener" "regr" {
  lb_listener_create = {
    name            = "rls${var.name_suffix}"
    description     = "regression-test listener"
    protocol        = "TCP"
    service_port    = 80
    loadbalancer_id = samsungcloudplatformv2_loadbalancer_loadbalancer.regr.id
    server_group_id = samsungcloudplatformv2_loadbalancer_lb_server_group.regr.id
    persistence     = "SOURCE_IP"
    routing_action  = "ROUNDROBIN"
  }
}
