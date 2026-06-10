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
# the pool subnet/VPC (409 Conflict). This fixture creates its own LB, so it leaks
# too. Until #77 is fixed the LB lane relies on the API reaper to sweep leaked LBs
# before the pool bootstrap is torn down
# (see docs/findings/loadbalancer-reap-strategy.md).

# LB public NAT IP integration fixture (self-contained). A public NAT IP attaches
# a public IP to a load balancer, so this scenario provisions the LB and then the
# public NAT IP on it. The resource takes a required parent `loadbalancer_id` plus
# a nested object `static_nat_create`.
#
# SELF-CONTAINED: the platform allows only ONE load balancer per subnet and
# rejects a 2nd create while the 1st is still CREATING (409), so LB scenarios
# cannot share one pool subnet. This fixture creates its OWN VPC + subnet + public
# IP and wires the LB / NAT IP to them via computed refs. All inputs have
# offline-safe defaults so `terraform validate` passes without credentials.

variable "name_suffix" {
  type        = string
  default     = ""
  description = "Per-run unique suffix (injected by the harness as TF_VAR_name_suffix)."
}

resource "samsungcloudplatformv2_vpc_vpc" "regr" {
  name        = "rlbpvpc${var.name_suffix}"
  cidr        = "192.168.0.0/24"
  description = "regr-test lb public nat ip vpc"
}

resource "samsungcloudplatformv2_vpc_subnet" "regr" {
  name            = "rlbpsub${var.name_suffix}"
  vpc_id          = samsungcloudplatformv2_vpc_vpc.regr.id
  type            = "GENERAL"
  cidr            = "192.168.0.0/27"
  description     = "regr-test lb public nat ip subnet"
  dns_nameservers = ["8.8.8.8"]
}

# A public NAT IP requires an Internet Gateway in the VPC (run 27210071644 400
# "No Internet Gateway (IGW) found in the VPC").
resource "samsungcloudplatformv2_vpc_internet_gateway" "regr" {
  type              = "IGW"
  vpc_id            = samsungcloudplatformv2_vpc_vpc.regr.id
  description       = "regr-test lb public nat ip igw"
  firewall_enabled  = true
  firewall_loggable = false
}

resource "samsungcloudplatformv2_vpc_publicip" "regr" {
  type        = "IGW"
  description = "regr-test lb public nat ip"
}

resource "samsungcloudplatformv2_loadbalancer_loadbalancer" "regr" {
  loadbalancer_create = {
    name                     = "rlbp${var.name_suffix}"
    description              = "regression-test-lb"
    layer_type               = "L4"
    firewall_enabled         = false
    firewall_logging_enabled = false
    vpc_id                   = samsungcloudplatformv2_vpc_vpc.regr.id
    subnet_id                = samsungcloudplatformv2_vpc_subnet.regr.id
  }
}

resource "samsungcloudplatformv2_loadbalancer_loadbalancer_public_nat_ip" "regr" {
  depends_on      = [samsungcloudplatformv2_vpc_internet_gateway.regr]
  loadbalancer_id = samsungcloudplatformv2_loadbalancer_loadbalancer.regr.id
  static_nat_create = {
    publicip_id = samsungcloudplatformv2_vpc_publicip.regr.id
  }
}
