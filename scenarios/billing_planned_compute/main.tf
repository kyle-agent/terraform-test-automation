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

# Promoted regression fixture: realistic planned-compute contract attributes,
# overridable via TF_VAR_*. Inputs are optional in the schema; defaults are
# schema-valid placeholders so the config passes `terraform validate` offline.

variable "account_id" {
  description = "SCP account UUID that owns the planned compute contract."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "service_id" {
  description = "Target compute service (virtual server) UUID."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "region" {
  description = "SCP region for the planned compute contract."
  type        = string
  default     = "kr-west1"
}

resource "samsungcloudplatformv2_billing_planned_compute" "regr" {
  account_id    = var.account_id
  action        = "CREATE"
  contract_type = "YEAR_1"
  os_type       = "LINUX"
  region        = var.region
  server_type   = "s1v1m2"
  service_id    = var.service_id
  service_name  = "regr-planned-compute"

  tags = {
    env = "regression"
  }
}
