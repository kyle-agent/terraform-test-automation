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
