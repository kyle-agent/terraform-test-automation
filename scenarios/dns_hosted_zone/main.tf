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

# DNS hosted zone regression fixture. The resource takes a single nested object
# attribute `hosted_zone_create`, modeled here as one object variable so the
# fixture passes `terraform validate` without credentials. The private_dns_id
# default is the zero-UUID placeholder; integration supplies a real private DNS id
# via TF_VAR_hosted_zone.
variable "hosted_zone" {
  type = object({
    description    = string
    name           = string
    private_dns_id = string
    type           = string
  })
  default = {
    description    = "regression-test hosted zone"
    name           = "regr.example.com"
    private_dns_id = "00000000-0000-0000-0000-000000000000"
    type           = "PRIVATE"
  }
  description = "DNS hosted zone create input; private_dns_id defaults to the zero-UUID and is supplied by integration."
}

resource "samsungcloudplatformv2_dns_hosted_zone" "regr" {
  hosted_zone_create = var.hosted_zone
}
