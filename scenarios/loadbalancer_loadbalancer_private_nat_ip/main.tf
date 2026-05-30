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

# LB private NAT IP regression fixture. The resource takes a required parent
# `loadbalancer_id` plus an optional nested object `private_static_nat_create`,
# modeled here as variables so the fixture passes `terraform validate` without
# credentials. All ids default to the zero-UUID; integration supplies real ids
# via TF_VAR_*.
variable "loadbalancer_id" {
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
  description = "Parent load balancer id; defaults to the zero-UUID and is supplied by integration."
}

variable "private_static_nat" {
  type = object({
    private_nat_id    = string
    private_nat_ip_id = string
  })
  default = {
    private_nat_id    = "00000000-0000-0000-0000-000000000000"
    private_nat_ip_id = "00000000-0000-0000-0000-000000000000"
  }
  description = "Private static NAT create input; ids default to the zero-UUID and are supplied by integration."
}

resource "samsungcloudplatformv2_loadbalancer_loadbalancer_private_nat_ip" "regr" {
  loadbalancer_id           = var.loadbalancer_id
  private_static_nat_create = var.private_static_nat
}
