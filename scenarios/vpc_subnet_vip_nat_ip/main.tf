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
  description = "Existing subnet VIP id to NAT. Integration runs override via TF_VAR_vip_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "publicip_id" {
  type        = string
  description = "Existing public IP id to bind to the VIP. Integration runs override via TF_VAR_publicip_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "nat_type" {
  type        = string
  description = "Static NAT type for the subnet VIP."
  default     = "PUBLIC"
}

# Subnet VIP NAT IP fixture guarding networking coverage: a static NAT binding a
# subnet VIP to a public IP must re-plan cleanly with no spurious update/replace.
# Required args: nat_type, publicip_id, subnet_id, vip_id.
resource "samsungcloudplatformv2_vpc_subnet_vip_nat_ip" "regr" {
  nat_type    = var.nat_type
  publicip_id = var.publicip_id
  subnet_id   = var.subnet_id
  vip_id      = var.vip_id
}
