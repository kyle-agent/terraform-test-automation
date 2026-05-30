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

variable "image_id" {
  type        = string
  description = "Bare metal OS image id. Integration supplies a real id via TF_VAR_image_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "os_user_id" {
  type        = string
  description = "OS administrator user id. Integration supplies a real id via TF_VAR_os_user_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "os_user_password" {
  type        = string
  description = "OS administrator password. Integration supplies a real value via TF_VAR_os_user_password."
  default     = "Regr1234!@"
  sensitive   = true
}

variable "region_id" {
  type        = string
  description = "Region id to provision in. Integration supplies a real id via TF_VAR_region_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "server_type_id" {
  type        = string
  description = "Bare metal server type id. Integration supplies a real id via TF_VAR_server_type_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "subnet_id" {
  type        = string
  description = "Subnet id for the server NIC. Integration supplies a real id via TF_VAR_subnet_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "vpc_id" {
  type        = string
  description = "VPC id. Integration supplies a real id via TF_VAR_vpc_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "bm_server_name" {
  type        = string
  description = "Name of the bare metal server. Integration overrides via TF_VAR_bm_server_name."
  default     = "regr-bm-server"
}

# Bare metal server fixture.
# Guards the bare metal provisioning path: required image/os user/region/subnet/
# vpc plus the required server_details list (name + type + nat flag). Disables
# NAT and hyper-threading for a deterministic single-node layout.
resource "samsungcloudplatformv2_baremetal_baremetal" "regr" {
  image_id         = var.image_id
  os_user_id       = var.os_user_id
  os_user_password = var.os_user_password
  region_id        = var.region_id
  subnet_id        = var.subnet_id
  vpc_id           = var.vpc_id

  server_details = [
    {
      bare_metal_server_name = var.bm_server_name
      server_type_id         = var.server_type_id
      nat_enabled            = false
      use_hyper_threading    = false
    }
  ]

  tags = {
    "regr" = "terraform"
  }
}
