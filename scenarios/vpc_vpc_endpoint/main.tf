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

# OBS is account-namespaced ({account_id}:{bucket} path form, cf. virtualserver
# image #86) and the doc example resource_key (07c5364702384471b650147321b52173)
# is a 32-hex id of the same shape as an account id - so for OBS the resource
# key is the ACCOUNT ID, not an IP (1.1.1.1 and the real OBS IP both 400ed).
variable "resource_key" {
  type        = string
  description = "Endpoint resource key (for OBS: the account id). Harness injects TF_VAR_resource_key or account id is used."
  default     = ""
}

variable "account_id" {
  type    = string
  default = "00000000000000000000000000000000"
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
  resource_info       = var.resource_info
  resource_key        = var.resource_key != "" ? var.resource_key : var.account_id
  resource_type       = var.resource_type
  subnet_id           = samsungcloudplatformv2_vpc_subnet.regr_endpoint.id
  vpc_id              = var.vpc_id
  description         = "regr-test"
}
