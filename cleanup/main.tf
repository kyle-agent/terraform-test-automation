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
