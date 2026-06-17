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

# Hosted-zone description; the only in-place-updatable field on this resource
# (the provider's Update rejects any change except description). The optional
# update stage mutates this via update.tfvars.
variable "hz_description" {
  type        = string
  description = "Hosted zone description (only in-place-updatable attribute)."
  default     = "regression-test hosted zone"
}

# DNS hosted zone regression fixture. A hosted zone requires a parent private
# DNS zone, so this fixture creates that prerequisite in-line (chained) and feeds
# its id into hosted_zone_create.private_dns_id. A second apply with no config
# change must re-plan cleanly.
resource "samsungcloudplatformv2_dns_private_dns" "parent" {
  private_dns_create = {
    description       = "regression-test parent private DNS for hosted zone"
    name              = "regr-hz-pdns${var.name_suffix}"
    connected_vpc_ids = [var.vpc_id]
  }
}

resource "samsungcloudplatformv2_dns_hosted_zone" "regr" {
  hosted_zone_create = {
    description    = var.hz_description
    name           = "regr${var.name_suffix}.example.com"
    private_dns_id = samsungcloudplatformv2_dns_private_dns.parent.id
    type           = "private"
  }
}
