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

# Per-run-unique suffix injected by the harness (TF_VAR_name_suffix).
variable "name_suffix" {
  type        = string
  description = "Per-run unique suffix appended to resource names."
  default     = ""
}

# Real VPC id supplied by the dependent-probe bootstrap via TF_VAR_vpc_id;
# defaults to the zero-UUID so the fixture validates offline.
variable "vpc_id" {
  type        = string
  description = "Existing VPC id for the private DNS zone. Integration overrides via TF_VAR_vpc_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

# Record description; an Optional, in-place-updatable attribute (no
# RequiresReplace, the provider's record Update PATCHes it). The optional update
# stage mutates this via update.tfvars.
variable "record_description" {
  type        = string
  description = "DNS record description (in-place-updatable attribute)."
  default     = "regression-test A record"
}

# DNS record regression fixture. A record requires a parent hosted zone, which in
# turn requires a private DNS zone, so this fixture creates both prerequisites
# in-line (chained) and feeds the hosted zone id into the record. A second apply
# with no config change must re-plan cleanly.
resource "samsungcloudplatformv2_dns_private_dns" "parent" {
  private_dns_create = {
    description       = "regression-test parent private DNS for record"
    name              = "regr-rec-pdns${var.name_suffix}"
    connected_vpc_ids = [var.vpc_id]
  }
}

resource "samsungcloudplatformv2_dns_hosted_zone" "parent" {
  hosted_zone_create = {
    description    = "regression-test parent hosted zone for record"
    name           = "regr${var.name_suffix}.example.com"
    private_dns_id = samsungcloudplatformv2_dns_private_dns.parent.id
    type           = "private"
  }
}

resource "samsungcloudplatformv2_dns_record" "regr" {
  hosted_zone_id = samsungcloudplatformv2_dns_hosted_zone.parent.id
  record_create = {
    name        = "www.regr${var.name_suffix}.example.com"
    type        = "A"
    ttl         = 300
    description = var.record_description
    records     = ["192.0.2.10"]
  }
}
