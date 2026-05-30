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

variable "backup_name" {
  type        = string
  description = "Name of the backup policy. Integration overrides via TF_VAR_backup_name."
  default     = "regr-backup"
}

variable "server_uuid" {
  type        = string
  description = "UUID of the virtual server to back up. Integration supplies a real id via TF_VAR_server_uuid."
  default     = "00000000-0000-0000-0000-000000000000"
}

# Backup policy fixture.
# Guards the agentless VM-image backup create path: required category/type/
# retention/server plus the required schedules list. Schedule uses a weekly
# full backup. Enum patterns: retention_period WEEK_2|MONTH_1|MONTH_3|MONTH_6|
# YEAR_1; schedule frequency MONTHLY|WEEKLY|DAILY; schedule type FULL|INCREMENTAL.
resource "samsungcloudplatformv2_backup_backup" "regr" {
  name             = var.backup_name
  encrypt_enabled  = true
  policy_category  = "AGENTLESS"
  policy_type      = "VM_IMAGE"
  retention_period = "WEEK_2"
  server_category  = "VIRTUAL_SERVER"
  server_uuid      = var.server_uuid

  schedules = [
    {
      frequency  = "WEEKLY"
      start_day  = "MON"
      start_time = "03:00:00"
      type       = "FULL"
    }
  ]

  tags = {
    "regr" = "terraform"
  }
}
