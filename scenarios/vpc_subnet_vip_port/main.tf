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
  description = "Existing subnet id holding the VIP. Integration runs override via TF_VAR_subnet_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "vip_id" {
  type        = string
  description = "Existing subnet VIP id to connect the port to. Integration runs override via TF_VAR_vip_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "port_id" {
  type        = string
  description = "Existing port id to attach behind the VIP. Integration runs override via TF_VAR_port_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

# Subnet VIP port fixture guarding networking coverage: a port attached behind a
# subnet VIP must re-plan cleanly with no spurious update or replacement.
# Required args: port_id, subnet_id, vip_id.
resource "samsungcloudplatformv2_vpc_subnet_vip_port" "regr" {
  port_id   = var.port_id
  subnet_id = var.subnet_id
  vip_id    = var.vip_id
}
