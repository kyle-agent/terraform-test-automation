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
  description = "Existing subnet id to create the port in. Integration runs override via TF_VAR_subnet_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "port_name" {
  type        = string
  description = "Name of the port."
  default     = "regr-port"
}

variable "fixed_ip_address" {
  type        = string
  description = "Fixed IP address to assign to the port (must fall within the subnet CIDR)."
  default     = "192.168.0.10"
}

# Port fixture guarding networking coverage: a port with a fixed IP in a subnet
# must re-plan cleanly with no spurious update or replacement.
# Required args: name, subnet_id. Optional: description, fixed_ip_address, tags.
resource "samsungcloudplatformv2_vpc_port" "regr" {
  name             = var.port_name
  subnet_id        = var.subnet_id
  fixed_ip_address = var.fixed_ip_address
  description      = "regr-test"
}
