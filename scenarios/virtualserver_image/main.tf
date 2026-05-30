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

variable "image_name" {
  type        = string
  description = "Name of the virtual server image. Integration overrides via TF_VAR_image_name."
  default     = "regr-ubuntu-2204-image"
}

variable "image_url" {
  type        = string
  description = "Source URL of the image file to register. Integration supplies a real object-storage URL via TF_VAR_image_url."
  default     = "https://example.invalid/images/ubuntu-22.04-server-cloudimg-amd64.qcow2"
}

# Virtual server image fixture.
# Guards the image registration path: required name plus an import source URL
# with explicit disk/container formats and an OS hint, so the optional+computed
# format fields stay stable and do not drift on re-plan.
resource "samsungcloudplatformv2_virtualserver_image" "regr" {
  name             = var.image_name
  url              = var.image_url
  disk_format      = "qcow2"
  container_format = "bare"
  os_distro        = "ubuntu"
  min_disk         = 10
  min_ram          = 1024
  visibility       = "private"
  protected        = false

  tags = {
    "regr" = "terraform"
  }
}
