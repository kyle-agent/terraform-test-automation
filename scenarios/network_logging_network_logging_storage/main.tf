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

variable "network_logging_bucket_name" {
  type        = string
  description = "Object storage bucket that receives network logs."
  default     = "regr-network-logs"
}

variable "network_logging_resource_type" {
  type        = string
  description = "Resource type whose traffic is logged. One of FIREWALL, SECURITY_GROUP, NAT."
  default     = "FIREWALL"
}

# Minimal network-logging-storage fixture guarding network_logging coverage;
# both attributes are required. resource_type enum per provider v3.3.1.
resource "samsungcloudplatformv2_network_logging_network_logging_storage" "regr" {
  bucket_name   = var.network_logging_bucket_name
  resource_type = var.network_logging_resource_type
}
