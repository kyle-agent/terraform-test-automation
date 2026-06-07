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

variable "server_name" {
  type        = string
  description = "Name of the virtual server. Integration overrides via TF_VAR_server_name."
  default     = "regr-server"
}

variable "keypair_name" {
  type        = string
  description = "Name of an existing keypair to inject. Integration supplies a real keypair via TF_VAR_keypair_name."
  default     = "regr-keypair"
}

variable "image_id" {
  type        = string
  description = "Boot image id. Integration supplies a real id via TF_VAR_image_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "server_type_id" {
  type        = string
  description = "Server type (flavor) id. Integration supplies a real id via TF_VAR_server_type_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "subnet_id" {
  type        = string
  description = "Subnet to attach the primary NIC to. Integration supplies a real id via TF_VAR_subnet_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

# Virtual server fixture.
# Guards the core compute create path: required boot_volume (single nested),
# keypair, image, server_type and the required networks map. The primary NIC is
# keyed by name so the provider's map-nested networks schema is exercised.
resource "samsungcloudplatformv2_virtualserver_server" "regr" {
  name           = var.server_name
  keypair_name   = var.keypair_name
  image_id       = var.image_id
  server_type_id = var.server_type_id

  # Workaround for provider bug #67: the Optional+Computed `state` is unknown when
  # omitted, but the Create guard checks only IsNull() (not IsUnknown()), so an
  # omitted state fails create with "Server state must be 'ACTIVE'". Setting it
  # explicitly lets us exercise the rest of the lifecycle. Remove once #67 is fixed.
  state = "ACTIVE"

  boot_volume = {
    size                  = 48 # must be divisible by 8 (API 400 otherwise; undocumented, no plan-time validator)
    type                  = "SSD"
    delete_on_termination = true
  }

  networks = {
    "nic0" = {
      subnet_id = var.subnet_id
    }
  }

  tags = {
    "regr" = "terraform"
  }
}
