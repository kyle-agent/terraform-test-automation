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

# The harness injects TF_VAR_account_id (the real test account) in every lane;
# the old trail_account_id variable was NEVER injected, so a zero-UUID was sent
# (one plausible cause of the 403).
variable "account_id" {
  type        = string
  description = "Owning account id; injected by the harness via TF_VAR_account_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

# Per-run unique suffix injected by the harness (TF_VAR_suffix).
variable "suffix" {
  type    = string
  default = ""
}

variable "trail_name" {
  type        = string
  description = "Name of the audit trail."
  default     = "regrtrail"
  # NOTE: overridden below with the per-run suffix to dodge 409 DBDuplicateEntry
}

# The trail API requires a REAL pre-existing OBS bucket (bucket_name) - create
# one on apply / delete on destroy via scripts/obs_bucket.py, same pattern as
# the network_logging fixture (OBS_BUCKET_SCRIPT + TF_VAR_obs_* come from the
# novpc lane environment).
locals {
  trail_bucket = "regrtrail${var.suffix}"
}

resource "terraform_data" "trail_bucket" {
  input = local.trail_bucket

  provisioner "local-exec" {
    command = "python3 \"$OBS_BUCKET_SCRIPT\" create \"${self.input}\""
  }
  provisioner "local-exec" {
    when    = destroy
    command = "python3 \"$OBS_BUCKET_SCRIPT\" delete \"${self.input}\""
  }
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
  account_id = var.account_id
  # Required by the provider schema (run 27409993978 failed validate without
  # it); same account since organization_trail_yn = "N".
  log_archive_account_id = var.account_id
  trail_name             = "${var.trail_name}${var.suffix}"
  trail_description      = "Regression fixture: organization-wide audit trail."
  bucket_name            = local.trail_bucket
  depends_on             = [terraform_data.trail_bucket]
  bucket_region          = var.trail_bucket_region
  trail_save_type        = "JSON"

  log_type_total_yn      = "Y"
  log_verification_yn    = "Y"
  organization_trail_yn  = "N"
  region_total_yn        = "Y"
  resource_type_total_yn = "Y"
  user_total_yn          = "Y"
}
