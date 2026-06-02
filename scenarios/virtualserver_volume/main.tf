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

variable "volume_name" {
  type        = string
  description = "Name of the standalone block volume. Integration overrides via TF_VAR_volume_name."
  default     = "regr-data-volume"
}

variable "volume_size" {
  type        = number
  description = "Size of the volume in GiB."
  default     = 100
}

# Virtual server (block) volume fixture.
# Guards an unattached data volume: required size plus an explicit volume_type
# and QoS ceilings, so the optional/computed volume_type does not drift between
# plans.
resource "samsungcloudplatformv2_virtualserver_volume" "regr" {
  name           = var.volume_name
  size           = var.volume_size
  volume_type    = "SSD"
  max_iops       = 15000
  max_throughput = 250

  tags = {
    "regr" = "terraform"
  }
}
