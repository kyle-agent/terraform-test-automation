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

variable "event_policy_object_type" {
  type        = string
  description = "Monitored object/product type the event policy applies to (e.g. VirtualServer)."
  default     = "VirtualServer"
}

variable "event_policy_metric_key" {
  type        = string
  description = "Metric key the event policy evaluates."
  default     = "cpu_usage"
}

variable "event_policy_event_level" {
  type        = string
  description = "Severity level raised when the policy fires."
  default     = "WARNING"
}

variable "event_policy_ft_count" {
  type        = number
  description = "Fault-tolerance count: consecutive breaches required before firing."
  default     = 3
}

variable "event_policy_disable_yn" {
  type        = string
  description = "Whether the event policy is disabled (Y/N)."
  default     = "N"
}

# Minimal CloudMonitoring event-policy fixture guarding event_policy coverage.
# All attributes are optional in the schema; a representative metric policy is
# defined so the resource re-plans cleanly. Override values via TF_VAR_*.
resource "samsungcloudplatformv2_cloudmonitoring_event_policy" "regr" {
  object_type          = var.event_policy_object_type
  metric_key           = var.event_policy_metric_key
  event_level          = var.event_policy_event_level
  ft_count             = var.event_policy_ft_count
  disable_yn           = var.event_policy_disable_yn
  event_message_prefix = "regr"
}
