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

# LB public NAT IP integration fixture (self-contained). A public NAT IP attaches
# a public IP to a load balancer, so this scenario provisions the LB and then the
# public NAT IP on it. vpc_id/subnet_id and the public IP (publicip_id) come from
# the dependent-probe bootstrap (TF_VAR_*). The resource takes a required parent
# `loadbalancer_id` plus a nested object `static_nat_create`. All inputs have
# offline-safe defaults so `terraform validate` passes without credentials.

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

variable "publicip_id" {
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
  description = "Public IP to attach. Integration supplies a real id via TF_VAR_publicip_id."
}

resource "samsungcloudplatformv2_loadbalancer_loadbalancer" "regr" {
  loadbalancer_create = {
    name                     = "rlbp${var.name_suffix}"
    description              = "regression-test-lb"
    layer_type               = "L4"
    firewall_enabled         = false
    firewall_logging_enabled = false
    vpc_id                   = var.vpc_id
    subnet_id                = var.subnet_id
  }
}

resource "samsungcloudplatformv2_loadbalancer_loadbalancer_public_nat_ip" "regr" {
  loadbalancer_id = samsungcloudplatformv2_loadbalancer_loadbalancer.regr.id
  static_nat_create = {
    publicip_id = var.publicip_id
  }
}
