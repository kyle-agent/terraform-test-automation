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

# DNS private DNS regression fixture. The resource takes a single nested object
# attribute `private_dns_create`, modeled here as one object variable so the
# fixture passes `terraform validate` without credentials. connected_vpc_ids
# defaults to a zero-UUID placeholder; integration supplies real VPC ids via
# TF_VAR_private_dns.
variable "private_dns" {
  type = object({
    description       = string
    name              = string
    connected_vpc_ids = list(string)
  })
  default = {
    description       = "regression-test private DNS"
    name              = "regr-private-dns"
    connected_vpc_ids = ["00000000-0000-0000-0000-000000000000"]
  }
  description = "Private DNS create input; connected_vpc_ids defaults to the zero-UUID and is supplied by integration."
}

resource "samsungcloudplatformv2_dns_private_dns" "regr" {
  private_dns_create = var.private_dns
}
