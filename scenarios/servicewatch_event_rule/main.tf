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

variable "event_rule_service_id" {
  type        = string
  description = "ServiceWatch service ID the event rule belongs to. Override via TF_VAR_event_rule_service_id with a real service UUID."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "event_rule_name" {
  type        = string
  description = "Display name of the ServiceWatch event rule."
  default     = "regr-event-rule"
}

variable "event_rule_active_yn" {
  type        = string
  description = "Whether the event rule is active (Y/N)."
  default     = "Y"
}

variable "event_rule_description" {
  type        = string
  description = "Free-text description of the event rule (in-place updatable via UpdateEventRule)."
  default     = "Regression fixture: ServiceWatch event rule."
}

# Minimal ServiceWatch event-rule fixture guarding event_rule coverage. Only
# service_id is required; name/active flag added for a realistic re-plan check.
resource "samsungcloudplatformv2_servicewatch_event_rule" "regr" {
  service_id  = var.event_rule_service_id
  name        = var.event_rule_name
  active_yn   = var.event_rule_active_yn
  description = var.event_rule_description
}
