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

# KNOWN ISSUE -- provider #77 (LB destroy-leak): load balancer family resources
# APPLY and REPLAN cleanly but LEAK on destroy, and a leaked LB blocks teardown of
# the pool subnet/VPC (409 Conflict). Until #77 is fixed the LB lane relies on the
# API reaper to sweep leaked LBs before the pool bootstrap is torn down
# (see docs/findings/loadbalancer-reap-strategy.md).

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
  name           = "rlbmv${var.name_suffix}"
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

# The API requires a load balancer to already exist in the subnet before a
# server group (and its members) can be created there (400: "the chosen subnet
# does not contain a Load Balancer"). So this fixture provisions its own LB in
# the same subnet first, then the server group + member on top.
resource "samsungcloudplatformv2_loadbalancer_loadbalancer" "regr" {
  loadbalancer_create = {
    name                     = "rlbm${var.name_suffix}"
    description              = "regression-test-lb"
    layer_type               = "L4"
    firewall_enabled         = false
    firewall_logging_enabled = false
    vpc_id                   = var.vpc_id
    subnet_id                = var.subnet_id
  }
}

resource "samsungcloudplatformv2_loadbalancer_lb_server_group" "regr" {
  depends_on = [samsungcloudplatformv2_loadbalancer_loadbalancer.regr]
  lb_server_group_create = {
    name        = "rlbms${var.name_suffix}"
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
    name          = "rlbmb${var.name_suffix}"
    member_ip     = samsungcloudplatformv2_virtualserver_server.regr.networks["nic0"].fixed_ip
    member_port   = 80
    member_weight = 1
    member_state  = "ENABLE" # enum: ENABLE | DISABLE
    object_id     = samsungcloudplatformv2_virtualserver_server.regr.id
    object_type   = "VM" # enum: VM | BM | MANUAL | MNGC; VM requires object_id
  }
}
