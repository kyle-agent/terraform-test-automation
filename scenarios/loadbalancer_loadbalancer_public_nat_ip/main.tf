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

# LB public NAT IP regression fixture. The resource takes a required parent
# `loadbalancer_id` plus an optional nested object `static_nat_create`, modeled
# here as variables so the fixture passes `terraform validate` without
# credentials. All ids default to the zero-UUID; integration supplies real ids
# via TF_VAR_*.
variable "loadbalancer_id" {
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
  description = "Parent load balancer id; defaults to the zero-UUID and is supplied by integration."
}

variable "static_nat" {
  type = object({
    publicip_id = string
  })
  default = {
    publicip_id = "00000000-0000-0000-0000-000000000000"
  }
  description = "Public static NAT create input; publicip_id defaults to the zero-UUID and is supplied by integration."
}

resource "samsungcloudplatformv2_loadbalancer_loadbalancer_public_nat_ip" "regr" {
  loadbalancer_id   = var.loadbalancer_id
  static_nat_create = var.static_nat
}
