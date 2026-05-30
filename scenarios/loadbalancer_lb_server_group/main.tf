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

# LB server group regression fixture. The resource takes a single nested object
# attribute `lb_server_group_create`, modeled here as one object variable so the
# fixture passes `terraform validate` without credentials. vpc_id/subnet_id/
# lb_health_check_id default to the zero-UUID; integration supplies real ids via
# TF_VAR_lb_server_group.
variable "lb_server_group" {
  type = object({
    name               = string
    description        = string
    protocol           = string
    lb_method          = string
    vpc_id             = string
    subnet_id          = string
    lb_health_check_id = string
  })
  default = {
    name               = "regr-test-sg"
    description        = "regression-test server group"
    protocol           = "TCP"
    lb_method          = "ROUND_ROBIN"
    vpc_id             = "00000000-0000-0000-0000-000000000000"
    subnet_id          = "00000000-0000-0000-0000-000000000000"
    lb_health_check_id = "00000000-0000-0000-0000-000000000000"
  }
  description = "LB server group create input; vpc_id/subnet_id/lb_health_check_id default to the zero-UUID and are supplied by integration."
}

resource "samsungcloudplatformv2_loadbalancer_lb_server_group" "regr" {
  lb_server_group_create = var.lb_server_group
}
