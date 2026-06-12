terraform {
  required_version = ">= 1.6"
  required_providers {
    samsungcloudplatformv2 = {
      source  = "SamsungSDSCloud/samsungcloudplatformv2"
      version = ">= 0.0.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}

provider "samsungcloudplatformv2" {}

# Promoted regression fixture: imports a PEM certificate + private key into the
# certificate manager. The earlier "500 ISE (platform)" was observed while
# sending a PLACEHOLDER PEM body; the API-suite proved certificate creation
# works on this account (self-sign lifecycle is green). So feed the API real,
# freshly generated self-signed PEM material via the tls provider instead of a
# placeholder. TF_VAR_cert_body / TF_VAR_private_key still override when set.

variable "cert_name" {
  description = "Display name of the managed certificate."
  type        = string
  default     = "regrcertificate"
}

variable "cert_body" {
  description = "PEM-encoded certificate body (empty => generate self-signed)."
  type        = string
  default     = ""
}

variable "private_key" {
  description = "PEM-encoded private key for the certificate (empty => generate)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "region" {
  description = "SCP region where the certificate is registered."
  type        = string
  default     = "kr-west1"
}

resource "tls_private_key" "regr" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "regr" {
  private_key_pem = tls_private_key.regr.private_key_pem

  subject {
    common_name  = "regr.example.com"
    organization = "Terraform Regression"
  }

  validity_period_hours = 72
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]
}

resource "samsungcloudplatformv2_certificate_manager" "regr" {
  cert_body   = var.cert_body != "" ? var.cert_body : tls_self_signed_cert.regr.cert_pem
  name        = var.cert_name
  private_key = var.private_key != "" ? var.private_key : tls_private_key.regr.private_key_pem
  region      = var.region
  timezone    = "Asia/Seoul"

  tags = {
    env = "regression"
  }
}
