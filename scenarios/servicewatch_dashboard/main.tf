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

variable "dashboard_name" {
  type        = string
  description = "Display name of the ServiceWatch dashboard."
  default     = "regr-dashboard"
}

# Minimal dashboard fixture guarding ServiceWatch dashboard coverage. Only
# name is user-settable; share_type/type/widgets are computed by the provider.
resource "samsungcloudplatformv2_servicewatch_dashboard" "regr" {
  name = var.dashboard_name
}
