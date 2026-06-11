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

# LB health check integration fixture. The platform requires a load balancer to
# already exist in the chosen subnet before a health check can be created there
# (400: "the chosen subnet does not contain a Load Balancer") -- the earlier
# assumption that a health check is LB-independent was wrong (confirmed by the
# green-56 regression). So this fixture provisions its own LB in the same subnet
# first (same pattern as loadbalancer_lb_member), then the health check on top.
# vpc_id/subnet_id come from the dependent-probe bootstrap (TF_VAR_*). With the
# patched provider (#77 wait-for-ACTIVE + clean destroy) the LB applies/destroys
# cleanly. All inputs have offline-safe defaults so `terraform validate` passes.

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

# The chosen subnet must contain a load balancer before the health check is
# created (see header). Provision one in the same subnet first.
resource "samsungcloudplatformv2_loadbalancer_loadbalancer" "regr" {
  loadbalancer_create = {
    name                     = "rhclb${var.name_suffix}"
    description              = "regression-test-lb for health check"
    layer_type               = "L4"
    firewall_enabled         = false
    firewall_logging_enabled = false
    vpc_id                   = var.vpc_id
    subnet_id                = var.subnet_id
  }
}

resource "samsungcloudplatformv2_loadbalancer_lb_health_check" "regr" {
  # Ensure the subnet already contains a load balancer before creating the check.
  depends_on = [samsungcloudplatformv2_loadbalancer_loadbalancer.regr]

  lb_health_check_create = {
    name                  = "rhc${var.name_suffix}"
    description           = "regression-test health check"
    protocol              = "TCP"
    health_check_port     = 80
    health_check_interval = 5
    health_check_timeout  = 5
    health_check_count    = 3
    vpc_id                = var.vpc_id
    subnet_id             = var.subnet_id
  }
}
