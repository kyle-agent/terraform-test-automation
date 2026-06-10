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

# For FS/OBS the provider docs say resource_key is an IP address ("1.1.1.1").
# This is the target service IP, NOT an address inside the pool subnet, so it is
# left as a routable-looking public-ish IP rather than a 192.168.0.0/27 address.
variable "resource_key" {
  type        = string
  description = "Endpoint resource key (for FS/OBS this is the target service IP)."
  default     = "1.1.1.1"
}

# For OBS the docs say resource_info is the service URL (https://xxx...).
variable "resource_info" {
  type        = string
  description = "Endpoint resource info (for OBS this is the service URL)."
  default     = "https://object-store.samsungsdscloud.com"
}

# endpoint_ip_address MUST sit inside the pool subnet CIDR 192.168.0.0/27
# (usable .1-.30). The bootstrap subnet is 192.168.0.0/27 and other pool
# scenarios consume low/high addresses (e.g. vip .20, bootstrap-side .30),
# so .12 is chosen to avoid the .1 gateway and known contended addresses.
variable "endpoint_ip_address" {
  type        = string
  description = "IP address for the endpoint, inside the pool subnet CIDR 192.168.0.0/27."
  default     = "192.168.0.12"
}

# VPC endpoint fixture guarding networking coverage: a private endpoint to a
# managed service (OBS) must re-plan cleanly with no spurious update/replace.
# Required args: endpoint_ip_address, name, resource_info, resource_key,
# resource_type, subnet_id, vpc_id. Optional: description, tags.
resource "samsungcloudplatformv2_vpc_vpc_endpoint" "regr" {
  endpoint_ip_address = var.endpoint_ip_address
  name                = "${var.endpoint_name}${var.name_suffix}"
  resource_info       = var.resource_info
  resource_key        = var.resource_key
  resource_type       = var.resource_type
  subnet_id           = var.subnet_id
  vpc_id              = var.vpc_id
  description         = "regr-test"
}
