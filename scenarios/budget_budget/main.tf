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

# Promoted regression fixture: monthly cost budget with notification and
# prevention nested blocks. Inputs are overridable via TF_VAR_*; schema-valid
# defaults keep `terraform validate` green offline.

variable "budget_name" {
  description = "Display name of the budget."
  type        = string
  default     = "regr-monthly-budget"
}

variable "budget_amount" {
  description = "Budget amount in the configured currency unit."
  type        = number
  default     = 1000000
}

variable "notification_receivers" {
  description = "Email recipients for budget notifications."
  type        = list(string)
  default     = ["regr@example.com"]
}

resource "samsungcloudplatformv2_budget_budget" "regr" {
  name        = var.budget_name
  amount      = var.budget_amount
  start_month = "2026-01"
  unit        = "KRW"

  notifications = {
    is_use_notification      = true
    notification_send_period = "DAILY"
    receivers                = var.notification_receivers
    thresholds               = [50, 80, 100]
  }

  prevention = {
    is_use_prevention = false
    receivers         = var.notification_receivers
    threshold         = 100
  }
}
