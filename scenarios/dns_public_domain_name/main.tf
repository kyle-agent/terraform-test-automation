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

# DNS public domain name regression fixture. The resource takes a single nested
# object attribute `public_domain_name_create`, modeled here as one object
# variable so the fixture passes `terraform validate` without credentials.
# Registrant contact fields use realistic placeholders; integration overrides
# real registrant data via TF_VAR_public_domain_name.
variable "public_domain_name" {
  type = object({
    name             = string
    description      = string
    address_type     = string
    auto_extension   = bool
    register_name_en = string
    register_email   = string
    register_telno   = string
    postal_code      = string
  })
  default = {
    name             = "regr.example.com"
    description      = "regression-test public domain"
    address_type     = "OVERSEAS"
    auto_extension   = false
    register_name_en = "Regression Test"
    register_email   = "dns-regr@example.com"
    register_telno   = "+82-2-0000-0000"
    postal_code      = "00000"
  }
  description = "Public domain name create input; registrant fields are placeholders overridden by integration."
}

resource "samsungcloudplatformv2_dns_public_domain_name" "regr" {
  public_domain_name_create = var.public_domain_name
}
