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

# File storage volume fixture.
# Guards the NFS share create path: required name/protocol/type_name.
# protocol pattern ^(NFS|CIFS)$; type_name pattern
# ^(HDD|SSD|HighPerformanceSSD|SSD_SAP_S|SSD_SAP_E)$.
resource "samsungcloudplatformv2_filestorage_volume" "regr" {
  name      = var.volume_name
  protocol  = "NFS"
  type_name = var.type_name

  tags = {
    "regr" = "terraform"
  }
}
