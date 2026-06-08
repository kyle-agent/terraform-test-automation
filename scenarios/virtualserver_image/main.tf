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

# Source URL of the image file to register.
#
# OFFLINE-SAFE DEFAULT: a dummy https URL so `terraform validate` (and any
# offline plan) succeeds without OBS creds or a real image. `validate` never
# fetches the URL, so this is harmless for static checks.
#
# INTEGRATION: CI supplies a real, fetchable object-storage URL via
# TF_VAR_image_url. Produce one with scripts/upload_image_to_obs.py, which
# uploads a qcow2 to OBS (SCP Object Storage) and prints the public object URL.
# See docs/findings/virtualserver-image-obs.md for the full approach + caveats.
variable "image_url" {
  type        = string
  description = "Fetchable URL of the qcow2 image to register. Integration supplies a real OBS object URL via TF_VAR_image_url."
  default     = "https://example.invalid/images/ubuntu-22.04-server-cloudimg-amd64.qcow2"
}

variable "image_disk_format" {
  type        = string
  description = "Disk format of the image file. qcow2 for the Ubuntu cloud image."
  default     = "qcow2"
}

variable "image_container_format" {
  type        = string
  description = "Container format of the image file."
  default     = "bare"
}

variable "image_os_distro" {
  type        = string
  description = "OS distro hint for the registered image. The platform validates os_distro against a server-side allow-list at import time (run 27124476579: 400 'Field os_distro is invalid. Example: alma'); 'cirros' is rejected. 'ubuntu' is accepted (the account's base images are Ubuntu). os_distro is metadata, so it need not match the CirrOS bits we stage."
  default     = "ubuntu"
}

variable "image_visibility" {
  type        = string
  description = "Image visibility. 'private' keeps the image scoped to the owning project."
  default     = "private"
}

# Virtual server image fixture.
#
# Registers a custom image from a URL (the url-based create path; instance_id is
# left unset, which selects CreateImage-from-URL in the provider). Only `name`
# is schema-required; disk_format / container_format / os_distro / visibility /
# min_disk / min_ram are Optional+Computed, but we set them explicitly so the
# computed values stay stable and do not drift on re-plan.
resource "samsungcloudplatformv2_virtualserver_image" "regr" {
  name             = var.image_name
  url              = var.image_url
  disk_format      = var.image_disk_format
  container_format = var.image_container_format
  os_distro        = var.image_os_distro
  min_disk         = 10
  min_ram          = 1024
  visibility       = var.image_visibility
  protected        = false

  tags = {
    "regr" = "terraform"
  }
}
