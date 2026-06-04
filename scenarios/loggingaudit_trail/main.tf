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

variable "trail_account_id" {
  type        = string
  description = "Account ID that owns the audit trail. Override via TF_VAR_trail_account_id with a real account UUID."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "trail_log_archive_account_id" {
  type        = string
  description = "Account ID where audit logs are archived. Override via TF_VAR_trail_log_archive_account_id with a real account UUID."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "trail_name" {
  type        = string
  description = "Name of the audit trail."
  default     = "regr-audit-trail"
}

variable "trail_bucket_name" {
  type        = string
  description = "Object storage bucket that receives the audit logs."
  default     = "regr-audit-bucket"
}

variable "trail_bucket_region" {
  type        = string
  description = "Region of the object storage bucket that receives the audit logs."
  default     = "kr-west1"
}

# Minimal LoggingAudit trail fixture guarding loggingaudit_trail coverage.
# The *_yn attributes are required Y/N flags; account IDs default to zero-UUIDs
# and should be overridden via TF_VAR_* for a real integration run.
resource "samsungcloudplatformv2_loggingaudit_trail" "regr" {
  account_id             = var.trail_account_id
  log_archive_account_id = var.trail_log_archive_account_id
  trail_name             = var.trail_name
  trail_description      = "Regression fixture: organization-wide audit trail."
  bucket_name            = var.trail_bucket_name
  bucket_region          = var.trail_bucket_region
  trail_save_type        = "JSON"

  log_type_total_yn      = "Y"
  log_verification_yn    = "Y"
  organization_trail_yn  = "N"
  region_total_yn        = "Y"
  resource_type_total_yn = "Y"
  user_total_yn          = "Y"
}
