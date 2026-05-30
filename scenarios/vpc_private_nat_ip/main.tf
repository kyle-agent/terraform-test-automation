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

variable "private_nat_id" {
  type        = string
  description = "Existing private NAT id to allocate the IP under. Integration runs override via TF_VAR_private_nat_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "ip_address" {
  type        = string
  description = "IP address to reserve within the private NAT range."
  default     = "192.168.64.10"
}

# Private NAT IP fixture guarding networking coverage: an IP reserved under a
# private NAT must re-plan cleanly with no spurious update or replacement.
# Required args: ip_address, private_nat_id. Optional: description.
resource "samsungcloudplatformv2_vpc_private_nat_ip" "regr" {
  ip_address     = var.ip_address
  private_nat_id = var.private_nat_id
  description    = "regr-test"
}
