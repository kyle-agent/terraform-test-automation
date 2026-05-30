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

variable "resource_type" {
  type        = string
  description = "VPC endpoint target resource type. Valid: FS, OBS, SCR, DNS."
  default     = "OBS"
}

variable "resource_key" {
  type        = string
  description = "Endpoint resource key (for OBS this is the target IP)."
  default     = "192.168.0.5"
}

variable "resource_info" {
  type        = string
  description = "Endpoint resource info (for OBS this is the service URL)."
  default     = "https://object-store.samsungsdscloud.com"
}

variable "endpoint_ip_address" {
  type        = string
  description = "IP address assigned to the endpoint inside the subnet CIDR."
  default     = "192.168.0.30"
}

# VPC endpoint fixture guarding networking coverage: a private endpoint to a
# managed service (OBS) must re-plan cleanly with no spurious update/replace.
# Required args: endpoint_ip_address, name, resource_info, resource_key,
# resource_type, subnet_id, vpc_id. Optional: description, tags.
resource "samsungcloudplatformv2_vpc_vpc_endpoint" "regr" {
  endpoint_ip_address = var.endpoint_ip_address
  name                = var.endpoint_name
  resource_info       = var.resource_info
  resource_key        = var.resource_key
  resource_type       = var.resource_type
  subnet_id           = var.subnet_id
  vpc_id              = var.vpc_id
  description         = "regr-test"
}
