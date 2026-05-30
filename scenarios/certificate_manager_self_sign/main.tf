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

# Promoted regression fixture: generates a self-signed certificate with a real
# CN, validity window and organization. Override via TF_VAR_*; schema-valid
# defaults keep `terraform validate` green offline.

variable "cert_name" {
  description = "Display name of the self-signed certificate."
  type        = string
  default     = "regr-self-signed"
}

variable "common_name" {
  description = "Certificate Common Name (CN)."
  type        = string
  default     = "regr.example.com"
}

variable "region" {
  description = "SCP region where the certificate is registered."
  type        = string
  default     = "kr-west1"
}

resource "samsungcloudplatformv2_certificate_manager_self_sign" "regr" {
  cn            = var.common_name
  name          = var.cert_name
  not_before_dt = "2026-01-01T00:00:00Z"
  not_after_dt  = "2027-01-01T00:00:00Z"
  organization  = "Regression Org"
  region        = var.region
  timezone      = "Asia/Seoul"

  tags = {
    env = "regression"
  }
}
