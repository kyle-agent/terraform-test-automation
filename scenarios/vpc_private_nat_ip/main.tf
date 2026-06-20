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

# Self-contained private-NAT-IP fixture. An IP reservation needs a parent private
# NAT, which in turn needs a transit gateway service resource — neither is
# provided by the bootstrap, so the full chain (transit gateway -> private NAT ->
# private NAT IP) is built here. No VPC is consumed, staying within the quota.
variable "name_suffix" {
  type        = string
  description = "Per-run unique suffix appended to resource names."
  default     = ""
}

variable "vpc_id" {
  type        = string
  description = "Existing VPC id connected to the transit gateway so it becomes Connectable. Integration runs override via TF_VAR_vpc_id."
  default     = "00000000-0000-0000-0000-000000000000"
}

variable "private_nat_cidr" {
  type        = string
  description = "IP range allocated to the private NAT."
  default     = "192.168.64.0/24"
}

variable "ip_address" {
  type        = string
  description = "IP address to reserve within the private NAT range."
  default     = "192.168.64.10"
}

variable "product_type" {
  type        = string
  description = "Transit gateway firewall product type. Valid: TGW_IGW, TGW_GGW, TGW_DGW, TGW_BM."
  default     = "TGW_BM"
}

resource "samsungcloudplatformv2_vpc_transit_gateway" "regr" {
  name        = "regr-pni-tgw${var.name_suffix}"
  description = "regr-test"
}

# A freshly created TGW is not "Connectable" until a VPC is attached to it. Attach
# the bootstrap VPC so the TGW becomes Connectable before the private NAT binds.
resource "samsungcloudplatformv2_vpc_transit_gateway_vpc_connection" "regr" {
  transit_gateway_id = samsungcloudplatformv2_vpc_transit_gateway.regr.id
  vpc_id             = var.vpc_id
}

# A private NAT requires the TGW to be Connectable = an ACTIVE firewall connection.
# The firewall_connection Create itself registers the firewall and waits ATTACHING
# -> ACTIVE; its only real prerequisite is a vpc_connection (proven by the green
# vpc_transit_gateway_firewall_connection scenario + fork PR #99). The separate
# vpc_transit_gateway_firewall resource is NOT needed (and is itself broken), so
# the chain is TGW -> vpc_connection -> firewall_connection.
resource "samsungcloudplatformv2_vpc_transit_gateway_firewall_connection" "regr" {
  transit_gateway_id = samsungcloudplatformv2_vpc_transit_gateway.regr.id

  depends_on = [samsungcloudplatformv2_vpc_transit_gateway_vpc_connection.regr]
}

resource "samsungcloudplatformv2_vpc_private_nat" "regr" {
  cidr                = var.private_nat_cidr
  name                = "regr-pnatip${var.name_suffix}"
  service_resource_id = samsungcloudplatformv2_vpc_transit_gateway.regr.id
  service_type        = "TRANSIT_GATEWAY"
  description         = "regr-test"

  depends_on = [
    samsungcloudplatformv2_vpc_transit_gateway_vpc_connection.regr,
    samsungcloudplatformv2_vpc_transit_gateway_firewall_connection.regr,
  ]
}

# IP reserved under the private NAT (top-level private_nat id used for chaining).
# ip_address must sit inside the private NAT range (var.private_nat_cidr). Derive it
# from the cidr with cidrhost so the pool lane's injected TF_VAR_ip_address (the
# bootstrap PUBLIC ip, ~123.x) cannot clobber it out of range.
resource "samsungcloudplatformv2_vpc_private_nat_ip" "regr" {
  ip_address     = cidrhost(var.private_nat_cidr, 10)
  private_nat_id = samsungcloudplatformv2_vpc_private_nat.regr.id
  description    = "regr-test"
}
