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

# LB health check regression fixture. The resource takes a single nested object
# attribute `lb_health_check_create`, modeled here as one object variable so the
# fixture passes `terraform validate` without credentials. vpc_id/subnet_id
# default to the zero-UUID; integration supplies real ids via TF_VAR_lb_health_check.
variable "lb_health_check" {
  type = object({
    name                  = string
    description           = string
    protocol              = string
    health_check_port     = number
    health_check_interval = number
    health_check_timeout  = number
    health_check_count    = number
    vpc_id                = string
    subnet_id             = string
  })
  default = {
    name                  = "regr-test-hc"
    description           = "regression-test health check"
    protocol              = "TCP"
    health_check_port     = 80
    health_check_interval = 5
    health_check_timeout  = 5
    health_check_count    = 3
    vpc_id                = "00000000-0000-0000-0000-000000000000"
    subnet_id             = "00000000-0000-0000-0000-000000000000"
  }
  description = "LB health check create input; vpc_id/subnet_id default to the zero-UUID and are supplied by integration."
}

resource "samsungcloudplatformv2_loadbalancer_lb_health_check" "regr" {
  lb_health_check_create = var.lb_health_check
}
