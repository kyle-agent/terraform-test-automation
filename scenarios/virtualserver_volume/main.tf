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
  description = "Size of the volume in GiB (documented minimum is 8)."
  default     = 8
}

# The volume has no description; tags are an in-place-updatable attribute
# (tag.UpdateTags in volume Update). The capability matrix update stage mutates
# this map rather than the riskier size-grow path.
variable "tags" {
  type        = map(string)
  description = "Resource tags (in-place-updatable via the volume tag update path)."
  default     = { "regr" = "terraform" }
}

# Virtual server (block) volume fixture.
# Guards an unattached data volume: required size plus an explicit volume_type,
# so the optional/computed volume_type does not drift between plans. max_iops
# and max_throughput are omitted because they are only valid for the
# SSD_Provisioned volume type.
resource "samsungcloudplatformv2_virtualserver_volume" "regr" {
  name        = var.volume_name
  size        = var.volume_size
  volume_type = "SSD"

  tags = var.tags
}
