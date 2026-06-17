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
  description = "Name of the file storage volume. Integration overrides via TF_VAR_volume_name."
  default     = "regrfsvol"
}

variable "type_name" {
  type        = string
  description = "File storage product type name. Integration supplies a real type via TF_VAR_type_name."
  default     = "HDD"
}

# Safe in-place-updatable flag: file_unit_recovery_enabled is Optional (no
# RequiresReplace) and is the ONLY field the volume Update method PATCHes
# (client.UpdateVolume sends just FileUnitRecoveryEnabled; tags are NOT PATCHed
# on update). The capability-matrix "update" stage (update.tfvars) flips this.
variable "file_unit_recovery_enabled" {
  type    = bool
  default = false
}

# File storage volume fixture.
# Guards the NFS share create path: required name/protocol/type_name.
# protocol pattern ^(NFS|CIFS)$; type_name pattern
# ^(HDD|SSD|HighPerformanceSSD|SSD_SAP_S|SSD_SAP_E)$.
resource "samsungcloudplatformv2_filestorage_volume" "regr" {
  name                       = var.volume_name
  protocol                   = "NFS"
  type_name                  = var.type_name
  file_unit_recovery_enabled = var.file_unit_recovery_enabled

  tags = {
    "regr" = "terraform"
  }
}
