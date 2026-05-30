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

# DNS record regression fixture. The resource takes a parent `hosted_zone_id`
# plus a single nested object attribute `record_create`, modeled here as
# variables so the fixture passes `terraform validate` without credentials.
# hosted_zone_id defaults to the zero-UUID; integration supplies a real zone id
# via TF_VAR_hosted_zone_id.
variable "hosted_zone_id" {
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
  description = "Parent hosted zone id; defaults to the zero-UUID and is supplied by integration."
}

variable "record" {
  type = object({
    name        = string
    type        = string
    ttl         = number
    description = string
    records     = list(string)
  })
  default = {
    name        = "www.regr.example.com"
    type        = "A"
    ttl         = 300
    description = "regression-test A record"
    records     = ["192.0.2.10"]
  }
  description = "DNS record create input (realistic A record with a TEST-NET-1 address)."
}

resource "samsungcloudplatformv2_dns_record" "regr" {
  hosted_zone_id = var.hosted_zone_id
  record_create  = var.record
}
