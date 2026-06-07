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

# Load balancer (the resource itself) integration fixture.
# Guards: a loadbalancer creates cleanly, a subsequent re-plan is idempotent
# (no spurious diff / replacement), and it destroys cleanly.
# The resource takes a single nested object attribute `loadbalancer_create`.
# vpc_id/subnet_id are bound from the dependent-probe bootstrap via TF_VAR_*.
# All inputs have offline-safe defaults so `terraform validate` passes without
# credentials. name carries the per-run suffix to avoid cross-run collisions.

variable "name_suffix" {
  type        = string
  default     = ""
  description = "Per-run unique suffix (injected by the harness as TF_VAR_name_suffix)."
}

variable "vpc_id" {
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
  description = "VPC for the load balancer. Integration supplies a real id via TF_VAR_vpc_id."
}

variable "subnet_id" {
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
  description = "Subnet for the load balancer. Integration supplies a real id via TF_VAR_subnet_id."
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
