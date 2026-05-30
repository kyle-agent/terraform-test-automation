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

# Promoted regression fixture: config-inspection diagnosis with required
# auth_key_request block and an optional schedule. UUID inputs default to the
# zero-UUID and are overridable via TF_VAR_*; passes validate offline.

variable "account_id" {
  description = "SCP account UUID running the inspection."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "diagnosis_account_id" {
  description = "Account UUID being diagnosed."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "auth_key_id" {
  description = "Auth key UUID granting inspection access."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "diagnosis_id" {
  description = "Diagnosis UUID."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

resource "samsungcloudplatformv2_configinspection" "regr" {
  account_id           = var.account_id
  csp_type             = "SCP"
  diagnosis_account_id = var.diagnosis_account_id
  diagnosis_check_type = "BP"
  diagnosis_id         = var.diagnosis_id
  diagnosis_name       = "regr-diagnosis"
  diagnosis_type       = "MANUAL"
  plan_type            = "BASIC"

  auth_key_request = {
    auth_key_id = var.auth_key_id
  }

  tags = {
    env = "regression"
  }
}
