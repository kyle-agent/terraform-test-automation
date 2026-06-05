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

variable "log_group_name" {
  type        = string
  description = "Name of the ServiceWatch log group created as the stream's parent."
  default     = "regr-log-stream-group"
}

variable "log_group_retention_period" {
  type        = number
  description = "Number of days to retain log entries in the parent group."
  default     = 30
}

variable "log_stream_name" {
  type        = string
  description = "Name of the ServiceWatch log stream."
  default     = "regrlogstream"
}

# Self-contained ServiceWatch log-stream fixture: a log stream requires an
# existing log group, so the parent group is created here and its id is wired
# into the stream's required log_group_id.
resource "samsungcloudplatformv2_servicewatch_log_group" "regr" {
  name             = var.log_group_name
  retention_period = var.log_group_retention_period
}

resource "samsungcloudplatformv2_servicewatch_log_stream" "regr" {
  log_group_id = samsungcloudplatformv2_servicewatch_log_group.regr.id
  name         = var.log_stream_name
}
