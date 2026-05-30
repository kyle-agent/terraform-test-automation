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

variable "log_group_name" {
  type        = string
  description = "Name of the ServiceWatch log group."
  default     = "regr-log-group"
}

variable "log_group_retention_period" {
  type        = number
  description = "Number of days to retain log entries in the group."
  default     = 30
}

# Minimal ServiceWatch log-group fixture guarding log_group coverage; both
# attributes are required so a fresh group must re-plan with no spurious diff.
resource "samsungcloudplatformv2_servicewatch_log_group" "regr" {
  name             = var.log_group_name
  retention_period = var.log_group_retention_period
}
