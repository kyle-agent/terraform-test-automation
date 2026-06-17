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

# LB health check integration fixture. A health check is independent of a load
# balancer (it binds directly to a vpc/subnet), so this scenario is self-contained:
# it only needs vpc_id/subnet_id from the dependent-probe bootstrap (TF_VAR_*).
# The resource takes a single nested object `lb_health_check_create`. All inputs
# have offline-safe defaults so `terraform validate` passes without credentials.

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

# In-place-updatable health-check description (lb_health_check_create.description is
# Optional, no RequiresReplace; the provider's UpdateLbHealthCheck PATCHes it). The
# capability-matrix update stage overrides it; the default keeps create + offline
# validate unchanged.
variable "health_check_description" {
  type        = string
  default     = "regression-test health check"
  description = "LB health check description (in-place updatable)."
}

resource "samsungcloudplatformv2_loadbalancer_lb_health_check" "regr" {
  lb_health_check_create = {
    name                  = "rhc${var.name_suffix}"
    description           = var.health_check_description
    protocol              = "TCP"
    health_check_port     = 80
    health_check_interval = 5
    health_check_timeout  = 5
    health_check_count    = 3
    vpc_id                = var.vpc_id
    subnet_id             = var.subnet_id
  }
}
