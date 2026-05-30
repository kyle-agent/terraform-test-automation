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

variable "volume_id" {
  type        = string
  description = "File storage volume id to schedule snapshots for. Integration supplies a real id via TF_VAR_volume_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

# File storage snapshot schedule fixture.
# Guards the periodic snapshot policy: required volume_id plus a weekly schedule
# (day/hour) and a retention count, exercising the single nested
# snapshot_schedule block.
resource "samsungcloudplatformv2_filestorage_snapshot_schedule" "regr" {
  volume_id               = var.volume_id
  snapshot_retention_count = 4

  # day_of_week pattern: ^(SUN|MON|TUE|WED|THU|FRI|SAT)$
  # hour pattern: ^([0-9]|1[0-9]|2[0-3])$ (no leading zero)
  snapshot_schedule = {
    frequency   = "WEEKLY"
    day_of_week = "MON"
    hour        = "3"
  }
}
