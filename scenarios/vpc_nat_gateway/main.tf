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

variable "publicip_id" {
  type        = string
  description = "Existing public IP id for the NAT gateway. Integration runs override via TF_VAR_publicip_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "subnet_id" {
  type        = string
  description = "Existing subnet id to place the NAT gateway in. Integration runs override via TF_VAR_subnet_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

# NAT gateway fixture guarding networking coverage: a NAT gateway bound to a
# subnet and a public IP must re-plan cleanly with no spurious update or replace.
# Required args: publicip_id, subnet_id. Optional: description, tags.
resource "samsungcloudplatformv2_vpc_nat_gateway" "regr" {
  publicip_id = var.publicip_id
  subnet_id   = var.subnet_id
  description = "regr-test"
}
