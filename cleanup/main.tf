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

# Read-only inventory of VPCs so we can identify leaked test resources
# (names created by this automation: regr-*, rpv*, rps*, rpsg*) before deleting
# anything. No resources are created or destroyed by this config.
data "samsungcloudplatformv2_vpc_vpcs" "all" {
  size = 50
}

output "all_vpcs" {
  value = [for v in data.samsungcloudplatformv2_vpc_vpcs.all.vpcs : {
    id    = v.id
    name  = v.name
    state = v.state
  }]
}

output "test_vpcs" {
  value = [for v in data.samsungcloudplatformv2_vpc_vpcs.all.vpcs :
    { id = v.id, name = v.name, state = v.state }
    if startswith(v.name, "regr") || startswith(v.name, "rpv") || startswith(v.name, "rps")
  ]
}

# VPC peerings — a leaked peering (from the failed vpc_vpc_peering create that
# still left a server-side object) blocks deleting its requester/approver VPC.
data "samsungcloudplatformv2_vpc_vpc_peerings" "all" {
  size = 50
}

output "peerings" {
  value = try([for p in data.samsungcloudplatformv2_vpc_vpc_peerings.all.vpc_peerings : {
    id        = p.id
    name      = p.name
    requester = p.requester_vpc_id
    approver  = p.approver_vpc_id
    state     = p.state
  }], "vpc_peerings is null/empty — see peering_total_count")
}

# inventory re-run 2026-06-04: pre-account-switch verification sweep

# account-switch verification 2026-06-04T09:11:34Z: list VPCs in the new account

# post-sweep verification 2026-06-04T10:04:11Z: list leaked VPCs after coverage sweep run 26943090696

# ---------------------------------------------------------------------------
# 2026-06-04: associated-resource inventory for the two leaked VPCs that fail
# to delete with 409 "Cannot terminate due to associated resources".
#   A (TGW shard): 02bbf96c66d14dd297d3fe8a5fe1cb72  name rpv269430906961
#   B (DNS shard): 8df00c61800d4ad9914cffb74d9a2149  name rpv269430906962
# READ-ONLY: data sources + outputs only; nothing is created or destroyed.
# All outputs use try(...) so a null/empty list does not fail the apply,
# mirroring the existing "peerings" output style above.
# ---------------------------------------------------------------------------

locals {
  leaked_vpc_ids = {
    A = "02bbf96c66d14dd297d3fe8a5fe1cb72"
    B = "8df00c61800d4ad9914cffb74d9a2149"
  }
}

# --- Subnets ------------------------------------------------------------
# NO vpc_id filter argument (verified in subnet_datasource.go: only cidr/id/
# name/page/size/sort/state are accepted). We list ALL subnets and filter by
# the item-level vpc_id field in HCL. Item linkage field: vpc_id (the subnet
# id also feeds subnet_vips below).
data "samsungcloudplatformv2_vpc_subnets" "all" {
  size = 10000
}

output "leaked_subnets" {
  value = try({ for k, vpc_id in local.leaked_vpc_ids : k => [
    for s in data.samsungcloudplatformv2_vpc_subnets.all.subnets : {
      id     = s.id
      name   = s.name
      vpc_id = s.vpc_id
      state  = s.state
    } if s.vpc_id == vpc_id
  ] }, "subnets null/empty")
}

# --- Internet gateways --------------------------------------------------
# Filter arg: vpc_id. Item linkage field: vpc_id.
data "samsungcloudplatformv2_vpc_internet_gateways" "leaked" {
  for_each = local.leaked_vpc_ids
  vpc_id   = each.value
}

output "leaked_internet_gateways" {
  value = try({ for k, ds in data.samsungcloudplatformv2_vpc_internet_gateways.leaked : k => [
    for g in ds.internet_gateways : {
      id     = g.id
      name   = g.name
      vpc_id = g.vpc_id
      state  = g.state
    }
  ] }, "internet_gateways null/empty")
}

# --- NAT gateways -------------------------------------------------------
# Filter arg: vpc_id (also subnet_id). Item linkage fields: vpc_id, subnet_id.
data "samsungcloudplatformv2_vpc_nat_gateways" "leaked" {
  for_each = local.leaked_vpc_ids
  vpc_id   = each.value
}

output "leaked_nat_gateways" {
  value = try({ for k, ds in data.samsungcloudplatformv2_vpc_nat_gateways.leaked : k => [
    for n in ds.nat_gateways : {
      id        = n.id
      name      = n.name
      vpc_id    = n.vpc_id
      subnet_id = n.subnet_id
      state     = n.state
    }
  ] }, "nat_gateways null/empty")
}

# --- Private NATs -------------------------------------------------------
# Filter arg: vpc_id. NOTE: list items have NO vpc_id field; the only linkage
# exposed per-item is service_resource_id/service_type. We filter by vpc_id so
# the returned set is already scoped to each leaked VPC.
data "samsungcloudplatformv2_vpc_private_nats" "leaked" {
  for_each = local.leaked_vpc_ids
  vpc_id   = each.value
}

output "leaked_private_nats" {
  value = try({ for k, ds in data.samsungcloudplatformv2_vpc_private_nats.leaked : k => [
    for p in ds.private_nats : {
      id                  = p.id
      name                = p.name
      service_resource_id = p.service_resource_id
      service_type        = p.service_type
      state               = p.state
    }
  ] }, "private_nats null/empty")
}

# --- Ports --------------------------------------------------------------
# NO vpc_id filter argument (only subnet_id / attached_resource_id, etc.).
# We list ALL ports and surface vpc_id + subnet_id so the two leaked VPC ids
# can be matched by eye.
data "samsungcloudplatformv2_vpc_ports" "all" {
}

output "all_ports" {
  value = try([for p in data.samsungcloudplatformv2_vpc_ports.all.ports : {
    id                     = p.id
    name                   = p.name
    vpc_id                 = p.vpc_id
    subnet_id              = p.subnet_id
    attached_resource_id   = p.attached_resource_id
    attached_resource_type = p.attached_resource_type
    state                  = p.state
  }], "ports null/empty")
}

# --- Subnet VIPs --------------------------------------------------------
# subnet_id is a REQUIRED arg and there is NO vpc_id filter; list items expose
# neither vpc_id nor subnet_id. We fan out over every subnet discovered in the
# two leaked VPCs (above) and key each VIP by its owning subnet_id so linkage
# is preserved. Empty when the leaked VPCs have no subnets.
locals {
  leaked_subnet_ids = toset([
    for s in data.samsungcloudplatformv2_vpc_subnets.all.subnets : s.id
    if contains(values(local.leaked_vpc_ids), s.vpc_id)
  ])
}

data "samsungcloudplatformv2_vpc_subnet_vips" "leaked" {
  for_each  = local.leaked_subnet_ids
  subnet_id = each.value
}

output "leaked_subnet_vips" {
  value = try({ for subnet_id, ds in data.samsungcloudplatformv2_vpc_subnet_vips.leaked : subnet_id => [
    for v in ds.subnet_vips : {
      id                 = v.id
      subnet_id          = subnet_id
      virtual_ip_address = v.virtual_ip_address
      state              = v.state
    }
  ] }, "subnet_vips null/empty")
}

# --- Transit gateways ---------------------------------------------------
# NOT VPC-scoped: NO vpc_id filter and list items expose NO vpc linkage field.
# Listed in full so the tgw ids can be fed into the connection lookup below.
data "samsungcloudplatformv2_vpc_transit_gateways" "all" {
  size = 100
}

output "all_transit_gateways" {
  value = try([for t in data.samsungcloudplatformv2_vpc_transit_gateways.all.tgws : {
    id    = t.id
    name  = t.name
    state = t.state
  }], "tgws null/empty")
}

# --- Transit gateway VPC connections ------------------------------------
# transit_gateway_id is a REQUIRED arg (also accepts a vpc_id filter). Item
# linkage fields: vpc_id, transit_gateway_id. We fan out over every TGW found
# above and surface vpc_id so the two leaked VPC ids can be matched by eye.
locals {
  transit_gateway_ids = toset([for t in data.samsungcloudplatformv2_vpc_transit_gateways.all.tgws : t.id])
}

data "samsungcloudplatformv2_vpc_transit_gateway_vpc_connections" "by_tgw" {
  for_each           = local.transit_gateway_ids
  transit_gateway_id = each.value
  size               = 100
}

output "transit_gateway_vpc_connections" {
  value = try({ for tgw_id, ds in data.samsungcloudplatformv2_vpc_transit_gateway_vpc_connections.by_tgw : tgw_id => [
    for c in ds.transit_gateway_vpc_connections : {
      id                 = c.id
      vpc_id             = c.vpc_id
      transit_gateway_id = c.transit_gateway_id
      vpc_name           = c.vpc_name
      state              = c.state
    }
  ] }, "transit_gateway_vpc_connections null/empty")
}

# --- DNS private DNS ----------------------------------------------------
# Filter arg: vpc_id. Item linkage field: connected_vpc_ids (a LIST of vpc ids).
# List attribute name is the SINGULAR "private_dns".
data "samsungcloudplatformv2_dns_private_dnss" "leaked" {
  for_each = local.leaked_vpc_ids
  vpc_id   = each.value
}

output "leaked_private_dnss" {
  value = try({ for k, ds in data.samsungcloudplatformv2_dns_private_dnss.leaked : k => [
    for d in ds.private_dns : {
      id                = d.id
      name              = d.name
      connected_vpc_ids = d.connected_vpc_ids
      state             = d.state
    }
  ] }, "private_dns null/empty")
}

# --- DNS hosted zones ---------------------------------------------------
# NO vpc_id filter (filters: name/type/status). Items link to a private DNS via
# private_dns_id / private_dns_name (which in turn carries connected_vpc_ids).
# Listed in full; correlate via the private_dns ids from leaked_private_dnss.
data "samsungcloudplatformv2_dns_hosted_zones" "all" {
}

output "all_hosted_zones" {
  value = try([for z in data.samsungcloudplatformv2_dns_hosted_zones.all.hosted_zones : {
    id               = z.id
    name             = z.name
    private_dns_id   = z.private_dns_id
    private_dns_name = z.private_dns_name
    status           = z.status
  }], "hosted_zones null/empty")
}

# --- DNS records --------------------------------------------------------
# NO vpc_id filter (filterable by hosted_zone_id/name/type/status). Items link
# to a zone via zone_id / zone_name. Listed in full; correlate to a leaked VPC
# through hosted_zone -> private_dns -> connected_vpc_ids.
data "samsungcloudplatformv2_dns_records" "all" {
}

output "all_records" {
  value = try([for r in data.samsungcloudplatformv2_dns_records.all.records : {
    id        = r.id
    name      = r.name
    zone_id   = r.zone_id
    zone_name = r.zone_name
    type      = r.type
    status    = r.status
  }], "records null/empty")
}
