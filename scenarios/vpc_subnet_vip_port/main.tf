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

# Self-contained subnet-VIP-port fixture. The vip_port binding needs a parent
# subnet VIP and a port, neither of which the bootstrap exports — so we create a
# subnet VIP and a port (both in the bootstrap subnet) inside this config and wire
# the binding to them. subnet_id comes from the bootstrap via TF_VAR_subnet_id.
variable "subnet_id" {
  type        = string
  description = "Existing subnet id (bootstrap subnet, 192.168.0.0/27). Integration runs override via TF_VAR_subnet_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "name_suffix" {
  type        = string
  description = "Per-run unique suffix appended to resource names."
  default     = ""
}

variable "vip_address" {
  type        = string
  description = "Virtual IP reserved in the bootstrap subnet CIDR."
  default     = "192.168.0.20"
}

variable "port_ip_address" {
  type        = string
  description = "Fixed IP for the port attached behind the VIP (within subnet CIDR)."
  default     = "192.168.0.10"
}

# Parent VIP reserved in the subnet.
resource "samsungcloudplatformv2_vpc_subnet_vip" "regr" {
  subnet_id          = var.subnet_id
  virtual_ip_address = var.vip_address
  description        = "regr-test"
}

# Port to place behind the VIP.
resource "samsungcloudplatformv2_vpc_port" "regr" {
  name             = "regr-vipport${var.name_suffix}"
  subnet_id        = var.subnet_id
  fixed_ip_address = var.port_ip_address
  description      = "regr-test"
}

# The VIP exposes its id under the computed nested object subnet_vip.id
# (no top-level id attribute on this resource).
resource "samsungcloudplatformv2_vpc_subnet_vip_port" "regr" {
  port_id   = samsungcloudplatformv2_vpc_port.regr.id
  subnet_id = var.subnet_id
  vip_id    = samsungcloudplatformv2_vpc_subnet_vip.regr.subnet_vip.id
}
