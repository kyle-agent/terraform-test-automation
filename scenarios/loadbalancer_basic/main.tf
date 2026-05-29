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

# Chapter 2 / provider issue #12 (loadbalancer family) regression fixture.
# Guards: a loadbalancer creates cleanly and a subsequent re-plan is idempotent
# (no spurious diff and no destroy+create replacement). The resource takes a
# single nested object attribute `loadbalancer_create`, so the whole input is
# modeled as one object variable; every field has a default so the fixture
# passes `terraform validate` (schema/type check) without credentials.
variable "loadbalancer" {
  type = object({
    description              = string
    firewall_enabled         = bool
    firewall_logging_enabled = bool
    layer_type               = string
    name                     = string
    service_ip               = string
    subnet_id                = string
    vpc_id                   = string
    source_nat_ip            = string
    health_check_ip_1        = string
    health_check_ip_2        = string
  })
  default = {
    description              = "regression-test-lb"
    firewall_enabled         = false
    firewall_logging_enabled = false
    health_check_ip_1        = null
    health_check_ip_2        = null
    layer_type               = "L4"
    name                     = "regr-test-lb"
    service_ip               = null
    source_nat_ip            = null
    subnet_id                = "00000000-0000-0000-0000-000000000000"
    vpc_id                   = "00000000-0000-0000-0000-000000000000"
  }
}

resource "samsungcloudplatformv2_loadbalancer_loadbalancer" "loadbalancer" {
  loadbalancer_create = var.loadbalancer
}
