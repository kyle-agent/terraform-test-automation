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

variable "log_stream_group_id" {
  type        = string
  description = "ID of the ServiceWatch log group that owns this stream. Override via TF_VAR_log_stream_group_id with a real log group UUID."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "log_stream_name" {
  type        = string
  description = "Name of the ServiceWatch log stream."
  default     = "regr-log-stream"
}

# Minimal ServiceWatch log-stream fixture guarding log_stream coverage; both
# attributes are required. log_group_id defaults to a zero-UUID placeholder.
resource "samsungcloudplatformv2_servicewatch_log_stream" "regr" {
  log_group_id = var.log_stream_group_id
  name         = var.log_stream_name
}
