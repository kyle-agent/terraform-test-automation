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

variable "vpc_id" {
  type        = string
  description = "Existing VPC id to create the endpoint in. Integration runs override via TF_VAR_vpc_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "subnet_id" {
  type        = string
  description = "Existing subnet id for the endpoint. Integration runs override via TF_VAR_subnet_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "endpoint_name" {
  type        = string
  description = "Endpoint name (3-20 chars, [a-zA-Z0-9-])."
  default     = "regr-endpoint"
}

# Per-run-unique suffix injected by the harness (TF_VAR_name_suffix).
variable "name_suffix" {
  type        = string
  description = "Per-run unique suffix appended to resource names."
  default     = ""
}

# resource_type enum, per provider schema/docs (vpc_endpoint.go Schema and
# docs/resources/vpc_vpc_endpoint.md): "FS | OBS | SCR | DNS".
# OBS (object storage) is the cheapest/most-available managed endpoint target.
variable "resource_type" {
  type        = string
  description = "VPC endpoint target resource type. Valid: FS, OBS, SCR, DNS."
  default     = "OBS"
}

# resource_key is an OPAQUE, server-issued 32-hex identifier (issue #94). It has
# NO client-derivable form: account_id, 1.1.1.1, and the real OBS IP were ALL
# 400-rejected by the backend ("Resource Key is not valid", runs 27401616476 /
# 27406093988 / 27419601096). The ONLY valid source is the discovery endpoint
# GET /v1/vpc-endpoints/connectable-resources?resource_type=OBS, whose items
# return {resource_info, resource_key, resource_type} for each connectable target.
# => The harness MUST inject a real key via TF_VAR_resource_key (look it up via
# that API for this account/region first). Leaving it empty makes create 400 by
# design; do NOT substitute account_id (that is the bug #94 documents).
variable "resource_key" {
  type        = string
  description = "Endpoint resource key: OPAQUE server-issued id from GET /v1/vpc-endpoints/connectable-resources (issue #94). Harness MUST inject TF_VAR_resource_key; no client-side formula exists."
  default     = ""
}

# For OBS the docs say resource_info is the service URL (https://xxx...).
variable "resource_info" {
  type        = string
  description = "Endpoint resource info (for OBS this is the service URL)."
  default     = "https://object-store.samsungsdscloud.com"
}

# The platform rejects endpoints on a GENERAL subnet with 400 "VPC Endpoint
# Type Subnet not found" (run 27121247070): the subnet create API takes a
# type enum (GENERAL | LOCAL | VPC_ENDPOINT), and an endpoint requires a
# VPC_ENDPOINT-type subnet. Create a dedicated one in the pool VPC
# (192.168.0.0/24; bootstrap occupies 192.168.0.0/27) instead of reusing the
# GENERAL pool subnet.
resource "samsungcloudplatformv2_vpc_subnet" "regr_endpoint" {
  name        = "regrepsub${var.name_suffix}"
  cidr        = "192.168.0.64/27"
  type        = "VPC_ENDPOINT"
  vpc_id      = var.vpc_id
  description = "regr vpc-endpoint-type subnet"
}

variable "endpoint_ip_address" {
  type        = string
  description = "IP address for the endpoint, inside the VPC_ENDPOINT subnet 192.168.0.64/27 (low addresses .65-.69 are platform-reserved)."
  default     = "192.168.0.70"
}

# VPC endpoint fixture guarding networking coverage: a private endpoint to a
# managed service (OBS) must re-plan cleanly with no spurious update/replace.
# Required args: endpoint_ip_address, name, resource_info, resource_key,
# resource_type, subnet_id, vpc_id. Optional: description, tags.
resource "samsungcloudplatformv2_vpc_vpc_endpoint" "regr" {
  endpoint_ip_address = var.endpoint_ip_address
  name                = "${var.endpoint_name}${var.name_suffix}"
  # resource_info should likewise come from the SAME connectable-resources item
  # as resource_key (the API returns them as a matched pair). The harness should
  # inject TF_VAR_resource_info alongside TF_VAR_resource_key.
  resource_info = var.resource_info
  # #94: pass the injected opaque key verbatim. Do NOT fall back to account_id
  # (backend 400s it); an empty value is meant to fail until a real key is wired.
  resource_key  = var.resource_key
  resource_type = var.resource_type
  subnet_id     = samsungcloudplatformv2_vpc_subnet.regr_endpoint.id
  vpc_id        = var.vpc_id
  description   = "regr-test"
}
