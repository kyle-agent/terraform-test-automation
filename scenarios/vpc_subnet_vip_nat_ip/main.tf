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

# Self-contained subnet-VIP static-NAT fixture. The static NAT binding needs a
# parent subnet VIP (not exported by the bootstrap), so we create the VIP here in
# the bootstrap subnet and bind it to the bootstrap public IP. subnet_id and
# publicip_id come from the bootstrap via TF_VAR_*.
variable "subnet_id" {
  type        = string
  description = "Existing subnet id (bootstrap subnet). Integration runs override via TF_VAR_subnet_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "publicip_id" {
  type        = string
  description = "Existing public IP id to bind to the VIP. Integration runs override via TF_VAR_publicip_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "vip_address" {
  type        = string
  description = "Virtual IP reserved in the bootstrap subnet CIDR. Defaults to null so the provider auto-assigns a free VIP and avoids collisions."
  default     = null
}

variable "nat_type" {
  type        = string
  description = "Static NAT type for the subnet VIP."
  default     = "PUBLIC"
}

# Parent VIP reserved in the subnet.
resource "samsungcloudplatformv2_vpc_subnet_vip" "regr" {
  subnet_id          = var.subnet_id
  virtual_ip_address = var.vip_address
  description        = "regr-test"
}

# Static NAT binding the VIP to the public IP. The VIP id is exposed under the
# computed nested object subnet_vip.id (no top-level id on the VIP resource).
resource "samsungcloudplatformv2_vpc_subnet_vip_nat_ip" "regr" {
  nat_type    = var.nat_type
  publicip_id = var.publicip_id
  subnet_id   = var.subnet_id
  vip_id      = samsungcloudplatformv2_vpc_subnet_vip.regr.subnet_vip.id
}
