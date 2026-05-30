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

# Promoted regression fixture: imports a PEM certificate + private key into the
# certificate manager. Real PEM material must be supplied via TF_VAR_cert_body /
# TF_VAR_private_key; the placeholder defaults are valid HCL for offline validate.

variable "cert_name" {
  description = "Display name of the managed certificate."
  type        = string
  default     = "regr-certificate"
}

variable "cert_body" {
  description = "PEM-encoded certificate body."
  type        = string
  default     = "-----BEGIN CERTIFICATE-----\nMIIBplaceholderregression\n-----END CERTIFICATE-----\n"
}

variable "private_key" {
  description = "PEM-encoded private key for the certificate."
  type        = string
  sensitive   = true
  default     = "-----BEGIN PRIVATE KEY-----\nMIIBplaceholderregression\n-----END PRIVATE KEY-----\n"
}

variable "region" {
  description = "SCP region where the certificate is registered."
  type        = string
  default     = "kr-west1"
}

resource "samsungcloudplatformv2_certificate_manager" "regr" {
  cert_body   = var.cert_body
  name        = var.cert_name
  private_key = var.private_key
  region      = var.region
  timezone    = "Asia/Seoul"

  tags = {
    env = "regression"
  }
}
