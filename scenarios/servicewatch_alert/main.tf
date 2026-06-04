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

variable "alert_name" {
  type        = string
  description = "Name of the ServiceWatch metric alert."
  default     = "regr-cpu-high"
}

variable "alert_level" {
  type        = string
  description = "Severity of the alert. One of HIGH, MIDDLE, LOW."
  default     = "HIGH"
}

variable "alert_namespace_name" {
  type        = string
  description = "Metric namespace the alert watches (e.g. a compute service namespace)."
  default     = "SCP/VirtualServer"
}

variable "alert_metric_name" {
  type        = string
  description = "Metric within the namespace to evaluate."
  default     = "CPUUtilization"
}

variable "alert_operator" {
  type        = string
  description = "Comparison operator. One of EQ, NOT_EQ, GT, GTE, LT, LTE, RANGE."
  default     = "GTE"
}

variable "alert_statistic" {
  type        = string
  description = "Statistic applied over the period. One of SUM, AVG, MAX, MIN."
  default     = "AVG"
}

variable "alert_threshold" {
  type        = number
  description = "Threshold compared against the statistic for non-RANGE operators."
  default     = 80
}

variable "alert_period" {
  type        = number
  description = "Evaluation period in minutes."
  default     = 5
}

# Minimal METRIC_ALERT fixture guarding ServiceWatch alert coverage: a fresh
# alert must re-plan cleanly with no spurious diff. Enums per provider v3.3.1.
resource "samsungcloudplatformv2_servicewatch_alert" "regr" {
  name                = var.alert_name
  type                = "METRIC_ALERT"
  level               = var.alert_level
  namespace_name      = var.alert_namespace_name
  metric_name         = var.alert_metric_name
  operator            = var.alert_operator
  statistic           = var.alert_statistic
  threshold           = var.alert_threshold
  period              = var.alert_period
  dimensions          = []
  missing_data_option = "MISSING"
  description         = "Regression fixture: CPU utilization breach alert."
}
