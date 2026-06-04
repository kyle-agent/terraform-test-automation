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

# LB member integration fixture (self-contained, like ske_nodepool builds its own
# parent). A member registers a backend behind a server group; an INSTANCE member
# needs a real compute instance (object_id) and its private IP (member_ip). So this
# scenario provisions: a virtual server (the backend) + a server group + the member
# that ties them together. Network/image/keypair/server_type come from the
# dependent-probe bootstrap (TF_VAR_*). member_ip is taken from the server's
# computed primary-NIC fixed_ip so it always matches the real backend. All inputs
# have offline-safe defaults so `terraform validate` passes without credentials.

variable "name_suffix" {
  type        = string
  default     = ""
  description = "Per-run unique suffix (injected by the harness as TF_VAR_name_suffix)."
}

variable "vpc_id" {
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
  description = "VPC for the server group. Integration supplies a real id via TF_VAR_vpc_id."
}

variable "subnet_id" {
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
  description = "Subnet for the backend NIC / server group. Integration supplies a real id via TF_VAR_subnet_id."
}

variable "keypair_name" {
  type        = string
  default     = "regr-keypair"
  description = "Keypair for the backend server. Integration supplies a real keypair via TF_VAR_keypair_name."
}

variable "image_id" {
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
  description = "Boot image id for the backend server. Integration supplies a real id via TF_VAR_image_id."
}

variable "server_type_id" {
  type        = string
  default     = "00000000-0000-0000-0000-000000000000"
  description = "Server type (flavor) id. Integration supplies a real id via TF_VAR_server_type_id."
}

# Backend instance the member points at.
resource "samsungcloudplatformv2_virtualserver_server" "regr" {
  name           = "rmsv${var.name_suffix}"
  keypair_name   = var.keypair_name
  image_id       = var.image_id
  server_type_id = var.server_type_id
  state          = "ACTIVE" # provider #67 workaround (omitted state fails create)

  boot_volume = {
    size                  = 48
    type                  = "SSD"
    delete_on_termination = true
  }

  networks = {
    "nic0" = {
      subnet_id = var.subnet_id
    }
  }
}

resource "samsungcloudplatformv2_loadbalancer_lb_server_group" "regr" {
  lb_server_group_create = {
    name        = "rsg${var.name_suffix}"
    description = "regression-test server group"
    protocol    = "TCP"
    lb_method   = "ROUND_ROBIN"
    vpc_id      = var.vpc_id
    subnet_id   = var.subnet_id
  }
}

resource "samsungcloudplatformv2_loadbalancer_lb_member" "regr" {
  lb_server_group_id = samsungcloudplatformv2_loadbalancer_lb_server_group.regr.id
  lb_member_create = {
    name          = "rmb${var.name_suffix}"
    member_ip     = samsungcloudplatformv2_virtualserver_server.regr.networks["nic0"].fixed_ip
    member_port   = 80
    member_weight = 1
    member_state  = "ENABLED"
    object_id     = samsungcloudplatformv2_virtualserver_server.regr.id
    object_type   = "INSTANCE"
  }
}
