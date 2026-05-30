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

# LB listener regression fixture. The resource takes a single nested object
# attribute `lb_listener_create`, modeled here as one object variable so the
# fixture passes `terraform validate` without credentials. loadbalancer_id and
# server_group_id default to the zero-UUID; integration supplies real ids via
# TF_VAR_lb_listener.
variable "lb_listener" {
  type = object({
    name            = string
    description     = string
    protocol        = string
    service_port    = number
    loadbalancer_id = string
    server_group_id = string
    persistence     = string
    routing_action  = string
  })
  default = {
    name            = "regr-test-listener"
    description     = "regression-test listener"
    protocol        = "TCP"
    service_port    = 80
    loadbalancer_id = "00000000-0000-0000-0000-000000000000"
    server_group_id = "00000000-0000-0000-0000-000000000000"
    persistence     = "SOURCE_IP"
    routing_action  = "ROUNDROBIN"
  }
  description = "LB listener create input; loadbalancer_id/server_group_id default to the zero-UUID and are supplied by integration."
}

resource "samsungcloudplatformv2_loadbalancer_lb_listener" "regr" {
  lb_listener_create = var.lb_listener
}
