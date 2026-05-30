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
  description = "Name of the bare metal block storage volume. Integration overrides via TF_VAR_volume_name."
  default     = "regr-bm-blockvol"
}

variable "volume_size_gb" {
  type        = number
  description = "Volume capacity in GB (min 1, max 16384)."
  default     = 100
}

variable "attach_object_id" {
  type        = string
  description = "Id of the bare metal server to attach to. Integration supplies a real id via TF_VAR_attach_object_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

# Bare metal block storage volume fixture.
# Guards the BM block volume create+attach path: required name/disk_type/size_gb
# plus the required attachments list (object_id + object_type) and the optional
# single qos block. disk_type pattern SSD|HDD; qos iops 5000-20000,
# throughput 250-1000.
resource "samsungcloudplatformv2_baremetal_blockstorage_volume" "regr" {
  name      = var.volume_name
  disk_type = "SSD"
  size_gb   = var.volume_size_gb

  attachments = [
    {
      object_id   = var.attach_object_id
      object_type = "BM"
    }
  ]

  qos = {
    iops       = 5000
    throughput = 250
  }

  tags = {
    "regr" = "terraform"
  }
}
