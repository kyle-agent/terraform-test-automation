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

variable "subnet_id" {
  type        = string
  description = "Existing subnet id to allocate the VIP in. Integration runs override via TF_VAR_subnet_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "virtual_ip_address" {
  type        = string
  description = "Virtual IP address to reserve within the subnet CIDR. Defaults to null so the provider auto-assigns a free VIP and avoids collisions."
  default     = null
}

# Subnet VIP fixture guarding networking coverage: a virtual IP reserved in a
# subnet must re-plan cleanly with no spurious update or replacement.
# Required arg: subnet_id. Optional: virtual_ip_address, description.
resource "samsungcloudplatformv2_vpc_subnet_vip" "regr" {
  subnet_id          = var.subnet_id
  virtual_ip_address = var.virtual_ip_address
  description        = "regr-test"
}
