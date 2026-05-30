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

# LB member regression fixture. The resource takes a required parent
# `lb_server_group_id` plus a nested object attribute `lb_member_create`,
# modeled here as variables so the fixture passes `terraform validate` without
# credentials. lb_server_group_id/object_id default to the zero-UUID; integration
# supplies real ids via TF_VAR_*.
variable "lb_server_group_id" {
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
  description = "Parent LB server group id; defaults to the zero-UUID and is supplied by integration."
}

variable "lb_member" {
  type = object({
    name          = string
    member_ip     = string
    member_port   = number
    member_weight = number
    member_state  = string
    object_id     = string
    object_type   = string
  })
  default = {
    name          = "regr-test-member"
    member_ip     = "192.0.2.20"
    member_port   = 80
    member_weight = 1
    member_state  = "ENABLED"
    object_id     = "00000000-0000-0000-0000-000000000000"
    object_type   = "INSTANCE"
  }
  description = "LB member create input; object_id defaults to the zero-UUID and is supplied by integration."
}

resource "samsungcloudplatformv2_loadbalancer_lb_member" "regr" {
  lb_server_group_id = var.lb_server_group_id
  lb_member_create   = var.lb_member
}
