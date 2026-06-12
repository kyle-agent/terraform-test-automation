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

variable "replication_name" {
  type        = string
  description = "Name of the replication volume created in the target region. Integration overrides via TF_VAR_replication_name."
  default     = "regrfsrepl"
}

variable "target_region" {
  type        = string
  description = "Target region for the replica. Same-region replication 400s 'Replication is not available.' (run 27409993978) - default to CROSS-region."
  default     = "kr-east1"
}

variable "volume_id" {
  type        = string
  description = "Source file storage volume id to replicate. Integration supplies a real id via TF_VAR_volume_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

# File storage replication fixture.
# Guards cross-region replication: required source volume_id + target region
# with a fixed replication frequency/type, plus a retention count.
# Enum patterns: replication_frequency ^(5min|hourly|daily|weekly|monthly)$,
# replication_type ^(replication|backup)$.
resource "samsungcloudplatformv2_filestorage_replication" "regr" {
  name                  = var.replication_name
  region                = var.target_region
  volume_id             = var.volume_id
  replication_frequency = "hourly"
  replication_type      = "replication"

  backup_retention_count = 7
}
