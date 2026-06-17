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

# Promoted regression fixture: a Direct Connect attached to a VPC with a
# bandwidth tier and firewall flags. vpc_id defaults to the zero-UUID and is
# overridable via TF_VAR_vpc_id; passes validate offline.

variable "vpc_id" {
  description = "VPC UUID the Direct Connect attaches to."
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "name" {
  description = "Direct Connect name."
  type        = string
  default     = "regr-direct-connect"
}

variable "bandwidth" {
  description = "Direct Connect bandwidth. Must be one of 1, 10, 20, 40."
  type        = number
  default     = 1
}

# In-place-updatable description (Optional, maxLength 50, no RequiresReplace; the
# provider's UpdateDirectConnect PATCHes only this field). The capability-matrix
# update stage overrides it; the default keeps create + offline validate unchanged.
variable "description" {
  description = "Direct Connect description (in-place updatable, maxLength 50)."
  type        = string
  default     = "Regression Direct Connect fixture"
}

resource "samsungcloudplatformv2_directconnect_direct_connect" "regr" {
  bandwidth         = var.bandwidth
  name              = var.name
  vpc_id            = var.vpc_id
  description       = var.description
  firewall_enabled  = true
  firewall_loggable = false

  tags = {
    env = "regression"
  }
}
